import AppKit
import SwiftUI
import QuartzCore

/// A pointer-transparent native tooltip window. It cannot steal chart hover or focus.
struct HistoryHoverPanel: NSViewRepresentable {
    var point: CGPoint?
    var content: AnyView?
    var cardHeight: CGFloat = 82
    var docking = false
    var dockFrame: CGRect?
    var onDocked: () -> Void = {}

    final class Coordinator {
        var animating = false
        let panel: NSPanel
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        init() {
            panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = host

        }
        func hide() { panel.orderOut(nil); animating = false }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        guard let point, let content, let window = view.window else { coordinator.hide(); return }
        if docking {
            guard !coordinator.animating, let dockFrame, dockFrame.width > 0, dockFrame.height > 0 else { return }
            coordinator.animating = true
            coordinator.host.rootView = AnyView(content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).preferredColorScheme(.dark))
            coordinator.host.sizingOptions = []
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.42
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                coordinator.panel.animator().setFrame(dockFrame, display: true)
            } completionHandler: { onDocked() }
            return
        }
        coordinator.host.rootView = AnyView(content.frame(width: 140, height: cardHeight, alignment: .top).preferredColorScheme(.dark))
        let size = coordinator.host.fittingSize
        let local = NSPoint(x: point.x, y: view.bounds.height - point.y)
        let anchor = window.convertPoint(toScreen: view.convert(local, to: nil))
        let screen = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        // Keep the complete chart clear, even when the pointer is above a short bar.
        let chartFrame = window.convertToScreen(view.convert(view.bounds, to: nil))
        // Follow on the trailing side of the pointer; the 22pt horizontal gap
        // keeps the active bar clear while allowing a closer vertical position.
        var origin = NSPoint(x: anchor.x + 22, y: anchor.y - size.height - 8)
        if origin.x + size.width > screen.maxX - 8 { origin.x = anchor.x - size.width - 22 }
        if docking { origin = NSPoint(x: chartFrame.maxX - size.width, y: chartFrame.minY - size.height - 8) }
        origin.x = max(screen.minX + 8, min(origin.x, screen.maxX - size.width - 8))
        if origin.y < screen.minY + 8 { origin.y = chartFrame.maxY + 16 }
        origin.y = min(origin.y, screen.maxY - size.height - 8)
        coordinator.panel.setFrame(NSRect(origin: origin, size: size), display: true)
        coordinator.panel.orderFrontRegardless()
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.hide() }
}

/// Reports the actual inline destination after layout, not an estimated offset.
struct DayDockTarget: NSViewRepresentable {
    var onFrame: (CGRect) -> Void
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            onFrame(window.convertToScreen(view.convert(view.bounds, to: nil)))
        }
    }
}
