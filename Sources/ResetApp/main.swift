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
    var menuBarItem: NSMenuItem?
    var alwaysOnItem: NSMenuItem?
    var activeAppItem: NSMenuItem?
    var menuActiveApp: VisibilityApp?
    var indicatorAlphaTarget: CGFloat = -1
    let notchAnimator = NotchAnimator()
    private var externalHoverTimer: Timer?
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
            self.updateIndicatorAppearance()
            if progress <= 0.001 && self.store.externalHoverOnly && !self.store.expanded,
               !(self.visibleNotchFrame?.insetBy(dx: -12, dy: -10).contains(self.lastPointer) ?? false),
               NSScreen.screens.contains(where: { $0.safeAreaInsets.top > 0 }) {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.store.externalHoverOnly, !self.store.expanded, self.store.islandProgress <= 0.001 else { return }
                    self.place()
                }
            }
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
        if let url = Bundle.main.url(forResource: "LeafTemplate", withExtension: "png"), let leaf = NSImage(contentsOf: url) {
            leaf.size = NSSize(width: 18, height: 18)
            leaf.isTemplate = true
            leaf.accessibilityDescription = "ResetMe usage"
            statusItem.button?.image = leaf
        }
        statusItem.button?.toolTip = "ResetMe"
        let menu = NSMenu(); menu.delegate = self
        let visibility = NSMenuItem(title: "Hide ResetMe", action: #selector(toggleVisibility), keyEquivalent: "")
        visibility.target = self; visibility.image = menuIcon("eye.slash"); menu.addItem(visibility); visibilityItem = visibility
        menu.addItem(.separator())
        let always = NSMenuItem(title: "Keep notch visible", action: #selector(toggleAlwaysOn), keyEquivalent: "")
        always.target = self; menu.addItem(always); alwaysOnItem = always
        let active = NSMenuItem(title: "Show while this app is active", action: #selector(toggleActiveApp), keyEquivalent: "")
        active.target = self; menu.addItem(active); activeAppItem = active
        menu.addItem(.separator())
        let menuBar = NSMenuItem(title: "Show in menu bar", action: #selector(toggleMenuBar), keyEquivalent: "")
        menuBar.target = self; menu.addItem(menuBar); menuBarItem = menuBar
        menu.addItem(.separator())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let versionItem = NSMenuItem(title: "ResetMe \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        item("Settings…", action: #selector(showSettings), menu: menu, symbol: "gearshape")
        item("Check for Updates…", action: #selector(checkForUpdates), menu: menu, symbol: "arrow.triangle.2.circlepath")
        menu.addItem(.separator())
        item("Quit ResetMe", action: #selector(quit), menu: menu, symbol: "power")
        // Reserve the same icon column in every section, including checkable rows.
        for entry in menu.items where !entry.isSeparatorItem {
            if entry.image == nil {
                entry.image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in true }
            }
            entry.image?.size = NSSize(width: 16, height: 16)
        }
        statusItem.menu = menu
        statusItem.isVisible = store.visibilitySettings.showInMenuBar
        store.visibilitySettings.onMenuBarChange = { [weak self] in
            guard let self else { return }
            self.statusItem.isVisible = self.store.visibilitySettings.showInMenuBar
        }
        place(); store.refresh()
        // Menu-bar and transparent-window areas do not reliably deliver mouseMoved.
        let hoverTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, NSScreen.screens.contains(where: { $0.safeAreaInsets.top == 0 }) else { return }
                self.updateHover(at: NSEvent.mouseLocation)
            }
        }
        externalHoverTimer = hoverTimer
        RunLoop.main.add(hoverTimer, forMode: .common)
        if CommandLine.arguments.contains("--prompting") { store.showPrompting(true) }
        if CommandLine.arguments.contains("--settings") { showSettings() }
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
    func menuIcon(_ symbol: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        image?.size = NSSize(width: 16, height: 16)
        image?.isTemplate = true
        return image
    }
    func item(_ title: String, action: Selector, menu: NSMenu, symbol: String? = nil) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self; entry.image = symbol.flatMap(menuIcon); menu.addItem(entry)
    }
    func targetScreen() -> NSScreen {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }) { return screen }
        if let screenID, let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == screenID }) { return screen }
        return NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens[0]
    }
    func place(on requestedScreen: NSScreen? = nil) {
        let screen = requestedScreen ?? targetScreen()
        screenID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        notchGeometry = NotchGeometry(screenFrame: screen.frame, safeTop: screen.safeAreaInsets.top, leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea)
        store.externalHoverOnly = notchGeometry == nil
        if notchGeometry == nil { notchGeometry = NotchGeometry(hoverScreenFrame: screen.frame) }
        store.hasNotch = true
        if let geometry = notchGeometry {
            store.notchSize = geometry.frame.size
            notchPanel.setFrame(IslandMotion.canvasFrame(geometry.frame), display: true)
        }
        resize(animated: false)
    }
    func updateHover(at point: NSPoint) {
        lastPointer = point
        guard !store.indicatorHidden else { return }
        // External displays have only an invisible top-center activation strip.
        if let screen = NSScreen.screens.first(where: { screen in
            screen.safeAreaInsets.top == 0 && CGRect(x: screen.frame.midX - 107, y: screen.frame.maxY - 28, width: 214, height: 29).contains(point)
        }), screenID != (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value {
            store.dismiss()
            place(on: screen)
        } else if store.externalHoverOnly && !store.expanded && store.islandProgress <= 0.001,
                  !(visibleNotchFrame?.insetBy(dx: -12, dy: -10).contains(point) ?? false),
                  NSScreen.screens.contains(where: { $0.safeAreaInsets.top > 0 }) {
            place()
        }
        updateNotchInteractivity()
        let activationFrame: CGRect?
        if store.externalHoverOnly && !store.expanded && store.islandProgress <= 0.001, let frame = notchGeometry?.frame {
            activationFrame = CGRect(x: frame.minX, y: frame.maxY - 28, width: frame.width, height: 29)
        } else { activationFrame = visibleNotchFrame?.insetBy(dx: -12, dy: -10) }
        let nearNotch = activationFrame?.contains(point) ?? false
        store.hover(nearNotch, region: "notch")
    }
    var visibleNotchFrame: CGRect? {
        notchGeometry.map { IslandMotion.frame(notch: $0.frame, expandedHeight: store.islandHeight, progress: store.islandProgress) }
    }
    func updateNotchInteractivity() {
        // Transparent canvas must never block the editor or menu items behind it.
        notchPanel.ignoresMouseEvents = store.indicatorHidden || !store.indicatorRevealed || !(visibleNotchFrame?.contains(lastPointer) ?? false)
    }
    func updateIndicatorAppearance() {
        let target: CGFloat = store.indicatorRevealed ? 1 : 0
        guard indicatorAlphaTarget != target else { return }
        indicatorAlphaTarget = target
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
            notchPanel.animator().alphaValue = target
        }
    }
    func resize(animated: Bool = true) {
        guard notchPanel != nil else { return }
        guard !store.indicatorHidden, notchGeometry != nil else {
            notchAnimator.stop(); notchPanel.orderOut(nil); return
        }
        let shouldAnimate = !store.externalHoverOnly && (animated || notchAnimator.isRunning) && notchPanel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        notchAnimator.move(to: store.expanded ? 1 : 0, animated: shouldAnimate)
        updateIndicatorAppearance()
        updateNotchInteractivity()
        notchPanel.orderFrontRegardless()
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menuBarItem?.state = store.visibilitySettings.showInMenuBar ? .on : .off
        alwaysOnItem?.state = store.visibilitySettings.alwaysOn ? .on : .off
        menuActiveApp = NSWorkspace.shared.frontmostApplication?.bundleURL.flatMap(VisibilityApp.init)
        if menuActiveApp?.id == Bundle.main.bundleIdentifier { menuActiveApp = nil }
        activeAppItem?.title = menuActiveApp.map { "Show with \($0.name)" } ?? "Show with active app"
        activeAppItem?.isEnabled = menuActiveApp != nil
        activeAppItem?.state = menuActiveApp.map { store.visibilitySettings.useActiveApps && store.visibilitySettings.selected.contains($0.id) } == true ? .on : .off
        visibilityItem?.title = store.hasNotch ? (store.indicatorHidden ? "Show notch" : "Hide notch") : "Notched display unavailable"
        visibilityItem?.image = menuIcon(store.indicatorHidden ? "eye" : "eye.slash")
        activeAppItem?.toolTip = "Keep the notch visible while this app is in the foreground."
        visibilityItem?.isEnabled = store.hasNotch
    }
    @objc func toggleMenuBar() { store.visibilitySettings.showInMenuBar.toggle() }
    @objc func toggleAlwaysOn() { store.visibilitySettings.alwaysOn.toggle() }
    @objc func toggleActiveApp() {
        guard let app = menuActiveApp else { return }
        let enabled = !(store.visibilitySettings.useActiveApps && store.visibilitySettings.selected.contains(app.id))
        store.visibilitySettings.setSelected(app, enabled: enabled)
        if enabled { store.visibilitySettings.useActiveApps = true }
        store.visibilitySettings.discover()
    }
    @objc func showSettings() { store.dismiss(); store.visibilitySettings.show() }
    @objc func toggleVisibility() { store.toggleIndicator() }
    @objc func checkForUpdates() { AppUpdater.shared.checkForUpdates() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        externalHoverTimer?.invalidate()
        MacTilt.shared.stop()
        store.shutdown()
        notchAnimator.stop()
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
