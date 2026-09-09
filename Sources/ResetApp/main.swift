import AppKit
import SwiftUI
import ResetCore

final class ResetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { (NSApp.delegate as? AppDelegate)?.store.dismiss() }
}
final class TrackingHost<Content: View>: NSHostingView<Content> {
    weak var store: UsageStore?
    var region = "panel"
    private var hoverArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { if region != "canvas" { store?.hover(true, region: region) } }
    override func mouseExited(with event: NSEvent) { if region != "canvas" { store?.hover(false, region: region) } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = UsageStore()
    var notchPanel: ResetPanel!
    var statusItem: NSStatusItem!
    var notchGeometry: NotchGeometry?
    var screenID: CGDirectDisplayID?
    var observers: [NSObjectProtocol] = []
    var wakeObserver: NSObjectProtocol?
    var pointerMonitor: Any?
    var localPointerMonitor: Any?
    var visibilityItem: NSMenuItem?
    let notchAnimator = NotchAnimator()
    var lastPointer = NSEvent.mouseLocation
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppUpdater.shared.start()
        notchPanel = makePanel(title: "ResetMe notch", size: store.notchSize)
        notchPanel.hasShadow = false
        // The contour straddles the menu-bar safe area and must remain visible there.
        notchPanel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        let notchHost = TrackingHost(rootView: IslandView(store: store)); notchHost.store = store; notchHost.region = "canvas"
        notchHost.sizingOptions = []
        notchPanel.contentView = notchHost
        notchAnimator.window = notchPanel
        notchAnimator.renderClosingTime = { [weak self] time in self?.store.motion.closingElapsed = time }
        notchAnimator.renderFill = { [weak self] fill in self?.store.motion.contourFill = fill }
        notchAnimator.render = { [weak self] progress in
            guard let self else { return }
            self.store.islandProgress = progress
            self.updateNotchInteractivity()
        }
        store.onExpand = { [weak self] _ in self?.resize() }
        store.onData = { [weak self] in self?.resize(animated: false) }
        store.onVisibility = { [weak self] in self?.resize(animated: false) }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.place() } })
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.store.menuTracking = true } })
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.store.menuTracking = false
                self.updateHover(at: NSEvent.mouseLocation)
            }
        })
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.store.refresh() } }
        // Mouse events in other apps cover the approach zone just outside our thin line.
        // This event type does not require Accessibility or input-monitoring permission.
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in self?.updateHover(at: NSEvent.mouseLocation) }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            if let window = event.window { self?.updateHover(at: window.convertPoint(toScreen: event.locationInWindow)) }
            return event
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.counterclockwise.circle", accessibilityDescription: "ResetMe usage")
        statusItem.button?.toolTip = "ResetMe"
        let menu = NSMenu(); menu.delegate = self
        let visibility = NSMenuItem(title: "Hide ResetMe", action: #selector(toggleVisibility), keyEquivalent: "")
        visibility.target = self; menu.addItem(visibility); visibilityItem = visibility
        item("Check for Updates…", action: #selector(checkForUpdates), menu: menu)
        menu.addItem(.separator())
        item("Quit ResetMe", action: #selector(quit), menu: menu)
        statusItem.menu = menu
        place(); store.refresh()
        if CommandLine.arguments.contains("--tune-reflections") { SceneSettings.shared.applyReflectionTune() }
        if CommandLine.arguments.contains("--hanging-light") {
            SceneSettings.shared.set("faceReflection", 0.35)
        }
        if CommandLine.arguments.contains("--top-center-light") {
            SceneSettings.shared.set("lightX", 0)
            SceneSettings.shared.set("lightY", 0)
        }
    }
    func makePanel(title: String, size: NSSize) -> ResetPanel {
        let window = ResetPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = title; window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1); window.hidesOnDeactivate = false; window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        window.acceptsMouseMovedEvents = true; window.isReleasedWhenClosed = false
        return window
    }
    func item(_ title: String, action: Selector, menu: NSMenu) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self; menu.addItem(entry)
    }
    func targetScreen() -> NSScreen {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }) { return screen }
        if let screenID, let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == screenID }) { return screen }
        return NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens[0]
    }
    func place() {
        let screen = targetScreen()
        screenID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        notchGeometry = NotchGeometry(screenFrame: screen.frame, safeTop: screen.safeAreaInsets.top, leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea)
        store.hasNotch = notchGeometry != nil
        if let geometry = notchGeometry {
            store.notchSize = geometry.frame.size
            notchPanel.setFrame(IslandMotion.canvasFrame(geometry.frame), display: true)
        }
        resize(animated: false)
    }
    func updateHover(at point: NSPoint) {
        lastPointer = point
        guard !store.indicatorHidden else { return }
        updateNotchInteractivity()
        let nearNotch = store.hasNotch && (visibleNotchFrame?.insetBy(dx: -12, dy: -10).contains(point) ?? false)
        store.hover(nearNotch, region: "notch")
    }
    var visibleNotchFrame: CGRect? {
        notchGeometry.map { IslandMotion.frame(notch: $0.frame, expandedHeight: store.islandHeight, progress: store.islandProgress) }
    }
    func updateNotchInteractivity() {
        // Transparent canvas must never block the editor or menu items behind it.
        notchPanel.ignoresMouseEvents = !(visibleNotchFrame?.contains(lastPointer) ?? false)
    }
    func resize(animated: Bool = true) {
        guard notchPanel != nil else { return }
        guard !store.indicatorHidden, notchGeometry != nil else {
            notchAnimator.stop(); notchPanel.orderOut(nil); return
        }
        let shouldAnimate = (animated || notchAnimator.isRunning) && notchPanel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        notchAnimator.move(to: store.expanded ? 1 : 0, animated: shouldAnimate)
        notchPanel.orderFrontRegardless()
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        visibilityItem?.title = store.hasNotch ? (store.indicatorHidden ? "Show ResetMe" : "Hide ResetMe") : "Notched display unavailable"
        visibilityItem?.isEnabled = store.hasNotch
    }
    @objc func toggleVisibility() { store.toggleIndicator() }
    @objc func checkForUpdates() { AppUpdater.shared.checkForUpdates() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        MacTilt.shared.stop()
        store.shutdown()
        notchAnimator.stop()
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
