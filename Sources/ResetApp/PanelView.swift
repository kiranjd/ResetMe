import SwiftUI
import AppKit
import ResetCore

private var themeAccent: Color { SceneSettings.shared.color("accent") }

struct IslandOutline: Shape {
    var progress: Double
    func path(in rect: CGRect) -> Path {
        let spread = IslandMotion.breadth(progress)
        let right = rect.maxX
        let radius = min(CGFloat(10 + 8 * spread), rect.height / 3)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: right, y: 0))
        path.addLine(to: CGPoint(x: right, y: rect.maxY - radius))
        path.addCurve(to: CGPoint(x: right - radius, y: rect.maxY), control1: CGPoint(x: right, y: rect.maxY - radius * 0.447715), control2: CGPoint(x: right - radius * 0.447715, y: rect.maxY))
        path.addLine(to: CGPoint(x: radius, y: rect.maxY))
        path.addCurve(to: CGPoint(x: 0, y: rect.maxY - radius), control1: CGPoint(x: radius * 0.447715, y: rect.maxY), control2: CGPoint(x: 0, y: rect.maxY - radius * 0.447715))
        path.closeSubpath()
        return path
    }
}

/// One screen-edge surface. The camera cutout is absorbed by its black background.
struct IslandView: View {
    @ObservedObject private var scene = SceneSettings.shared
    @ObservedObject var store: UsageStore
    @ObservedObject var motion: IslandPresentation
    init(store: UsageStore) { self.store = store; self.motion = store.motion }
    var progress: Double { motion.progress }
    var reveal: Double { IslandMotion.smooth((progress - 0.25) / 0.55) }
    var rubberStretch: CGFloat { 0 }
    var body: some View {
        GeometryReader { geometry in
            let virtualNotch = CGRect(x: (geometry.size.width - store.notchSize.width) / 2,
                                      y: geometry.size.height - store.notchSize.height,
                                      width: store.notchSize.width, height: store.notchSize.height)
            let surfaceFrame = IslandMotion.frame(notch: virtualNotch, expandedHeight: store.islandHeight, progress: progress)
            let surface = surfaceFrame.size
            ZStack(alignment: .top) {
                Color.black
                ExpandedTexture(active: store.expanded)
                    .opacity(reveal)
                    .allowsHitTesting(false)
                if progress > 0.001 {
                VStack(spacing: 0) {
                    HStack {
                        Group {
                            if store.promptingOpen { Text("Codex").font(.system(size: 10, weight: .medium)) }
                            else { ProviderPicker(store: store) }
                        }.frame(width: 65, height: store.notchSize.height - 7, alignment: .leading)
                        Spacer()
                        Button { if store.promptingOpen { store.prompting.refresh() } else { store.refresh() } } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10)).frame(width: 20, height: 24).matteContentShade()
                        }.buttonStyle(.plain).disabled(store.refreshing && !store.promptingOpen)
                            .accessibilityLabel(store.promptingOpen ? "Refresh prompting" : "Refresh usage").help(store.promptingOpen ? "Refresh local prompting history" : store.freshness)
                        Menu {
                            Button(store.indicatorHidden ? "Show ResetMe" : "Hide ResetMe") { store.toggleIndicator() }
                            Button("Settings…") { store.dismiss(); store.visibilitySettings.show() }
                            Button("Check for Updates…") { AppUpdater.shared.checkForUpdates() }
                            Divider()
                            Divider()
                            Button("Quit ResetMe") { NSApplication.shared.terminate(nil) }
                        } label: { Image(systemName: "ellipsis").frame(width: 16, height: 24).matteContentShade() }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20, height: 24).clipped().accessibilityLabel("ResetMe menu")
                    }.foregroundStyle(.secondary).padding(.horizontal, 16).frame(height: store.notchSize.height - 7)
                    HStack(spacing: 18) {
                        surfaceTab("Usage", prompting: false)
                        surfaceTab("Prompting", prompting: true)
                        Spacer()
                    }.padding(.horizontal, 22).frame(height: 32)
                    if store.promptingOpen { PromptingView(store: store.prompting) }
                    else { PanelView(store: store) }
                }.frame(width: 348, alignment: .top)
                    .opacity(reveal)
                    .blur(radius: 5 * (1 - reveal))
                    .offset(y: -10 * (1 - reveal))
                    .scaleEffect(0.995 + 0.005 * reveal, anchor: .top)
                    .allowsHitTesting(progress > 0.80)
                    .accessibilityHidden(progress < 0.80)
                    .frame(width: surface.width, height: surface.height, alignment: .top)
                }

            }
            .frame(width: surface.width, height: surface.height, alignment: .top)
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88), value: store.weeklyHistoryOpen)
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.9), value: store.dayCardHeight)
            .overlayPreferenceValue(QuotaAnchors.self) { anchors in
                GeometryReader { proxy in
                    let barBounds = anchors["bar"].map { proxy[$0] } ?? CGRect(x: 78, y: 85, width: 101, height: 5)
                    let bar = barBounds.insetBy(dx: barBounds.height / 2, dy: 0)
                    let t = CGFloat(IslandMotion.smooth(progress))
                    let value = store.sharedFiveHour
                    let remaining = value?.remaining ?? 0
                    let lineOpacity = IslandMotion.smooth(progress / 0.18)
                    let emergence = 1.0
                    let pulse = sin(Double.pi * emergence)
                    let inset: CGFloat = 0
                    let color: Color = value == nil ? .secondary : remaining < 5 ? BrandPalette.copper : remaining < 10 ? BrandPalette.sand : themeAccent
                    SharedQuotaLine(progress: progress, destination: bar, closingElapsed: store.expanded ? nil : motion.closingElapsed, origin: CGRect(x: virtualNotch.minX - IslandMotion.wingWidth - surfaceFrame.minX + inset, y: 0, width: store.notchSize.width + IslandMotion.wingWidth - 2 * inset, height: store.notchSize.height - inset))
                        .stroke(Color(white: 0.30), style: StrokeStyle(lineWidth: 2.5 + 2.5 * t, lineCap: .round, lineJoin: .round))
                        .opacity(lineOpacity * emergence * (store.promptingOpen ? 0 : 1))
                    SharedQuotaLine(progress: progress, destination: bar, closingElapsed: store.expanded ? nil : motion.closingElapsed, origin: CGRect(x: virtualNotch.minX - IslandMotion.wingWidth - surfaceFrame.minX + inset, y: 0, width: store.notchSize.width + IslandMotion.wingWidth - 2 * inset, height: store.notchSize.height - inset))
                        .trim(from: 0, to: remaining / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 2.5 + 2.5 * t, lineCap: .round, lineJoin: .round))
                        .shadow(color: color.opacity(pulse * 0.5), radius: 3 * pulse)
                        .opacity(lineOpacity * emergence * (store.promptingOpen ? 0 : 1))
                    let resting = CGRect(x: virtualNotch.minX - IslandMotion.wingWidth - surfaceFrame.minX, y: 0, width: store.notchSize.width + IslandMotion.wingWidth, height: store.notchSize.height)
                    SharedQuotaLine(progress: 0, destination: bar, closingElapsed: nil, origin: resting)
                        .stroke(Color(white: 0.30), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .opacity(1 - lineOpacity)
                    SharedQuotaLine(progress: 0, destination: bar, closingElapsed: nil, origin: resting)
                        .trim(from: 0, to: remaining / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .opacity(1 - lineOpacity)
                    if !store.expanded {
                        Text(value.map { "\(Int($0.remaining.rounded()))%" } ?? "—")
                            .font(.custom("Menlo-Bold", size: 11))
                            .foregroundStyle(color)
                            .opacity(1 - IslandMotion.smooth(progress / 0.25))
                            .position(x: virtualNotch.minX - surfaceFrame.minX - IslandMotion.wingWidth / 2 + 1,
                                      y: (store.notchSize.height - 3) / 2)
                    }

                }.allowsHitTesting(false)
            }
            .clipShape(IslandOutline(progress: progress))
            .scaleEffect(x: 1 + (store.expanded ? 0 : rubberStretch * 0.025), y: 1 + rubberStretch * 0.16, anchor: .topTrailing)
            .position(x: surfaceFrame.midX, y: surface.height / 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark).tint(themeAccent)
        .transaction { $0.animation = nil }
        .onExitCommand { store.dismiss() }
    }
    private func surfaceTab(_ title: String, prompting: Bool) -> some View {
        Button { store.showPrompting(prompting) } label: {
            VStack(spacing: 5) {
                Text(title).font(.system(size: 11, weight: .medium))
                Capsule().fill(store.promptingOpen == prompting ? BrandPalette.cream.opacity(0.65) : .clear).frame(height: 1.5)
            }.fixedSize(horizontal: true, vertical: false).frame(height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .foregroundStyle(BrandPalette.cream.opacity(store.promptingOpen == prompting ? 0.95 : 0.45))
            .accessibilityAddTraits(store.promptingOpen == prompting ? .isSelected : [])
    }
}

struct NotchContour: Shape {
    func path(in rect: CGRect) -> Path {
        // Keep the stroke outside the camera exclusion region, including the bottom corners.
        let inset: CGFloat = 3, radius: CGFloat = 10
        let left = rect.minX + inset, right = rect.maxX - inset, bottom = rect.maxY - inset
        var path = Path()
        path.move(to: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: bottom - radius))
        path.addQuadCurve(to: CGPoint(x: left + radius, y: bottom), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: right - radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: right, y: bottom - radius), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: right, y: rect.minY))
        return path
    }
}
struct PanelView: View {
    @ObservedObject private var scene = SceneSettings.shared
    @ObservedObject var store: UsageStore
    @ObservedObject var motion: IslandPresentation
    init(store: UsageStore) { self.store = store; self.motion = store.motion }
    var body: some View { detail.preferredColorScheme(.dark).tint(themeAccent) }
    var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.buckets.enumerated()), id: \.element.id) { index, bucket in
                        bucketRows(bucket)
                            .modifier(DescendingReveal(amount: IslandMotion.smooth((motion.progress - 0.35 - Double(index) * 0.12) / 0.30)))
                    }
                    if store.buckets.isEmpty {
                        Text(store.refreshing ? "Connecting…" : "Quota unavailable")
                            .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
                    }
                    if let error = store.error {
                        Text(error).font(.system(size: 11)).foregroundStyle(BrandPalette.sand)
                            .fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
                    }
                    if !store.buckets.contains(where: { $0.id == store.provider.rawValue && $0.windows.contains(where: { $0.windowDurationMins == 10080 }) }) {
                        if store.weeklyHistoryOpen {
                            WeeklyHistoryView(store: store).padding(.vertical, 8)
                        } else {
                            Button("Show local token history") { store.setHistoryOpen(true) }
                                .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(themeAccent)
                                .padding(.vertical, 7)
                        }
                    }
                    if store.weeklyHistoryOpen && !store.displayedCreditDates.isEmpty {
                        bankedResets
                            .modifier(DescendingReveal(amount: IslandMotion.smooth((motion.progress - 0.82) / 0.17)))
                    }

                }.padding(.horizontal, 18).padding(.bottom, 14)
            }
        }.frame(width: 348, height: store.detailHeight - 78 - 32)
    }
    var bankedResets: some View {
        HStack(spacing: 7) {
            Image(systemName: "clock").font(.system(size: 11))
            Text("Expires in").foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(store.displayedCreditDates.enumerated()), id: \.offset) { index, expiry in
                        if index > 0 { Text("·").foregroundStyle(.secondary) }
                        Text(resetExpiry(expiry))
                            .help(expiry?.formatted(date: .complete, time: .shortened) ?? "Expiry unavailable")
                            .accessibilityLabel("Banked reset \(index + 1), expires in \(resetExpiry(expiry))")
                    }
                }
            }.fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11, weight: .medium)).monospacedDigit()
        .foregroundStyle(themeAccent).frame(height: 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(store.displayedCreditDates.count) banked resets")
    }
    private func resetExpiry(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        let seconds = Int(date.timeIntervalSince(store.now))
        if seconds <= 0 { return "Expired" }
        if seconds >= 86400 { return "\(seconds / 86400)d \((seconds % 86400) / 3600)h" }
        return store.countdown(date)
    }

    func bucketRows(_ bucket: LimitBucket) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if bucket.id != store.provider.rawValue {
            HStack(alignment: .center) {
                Button { store.selectedID = bucket.id; store.onData?() } label: {
                    HStack(spacing: 6) {
                        Image(nsImage: NSImage(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("ProviderIcon-\(store.provider.rawValue).png")) ?? NSImage())
                            .resizable().renderingMode(.template).scaledToFit().frame(width: 13, height: 13).foregroundStyle(BrandPalette.cream.opacity(0.8)).accessibilityLabel(store.provider.displayName)
                        Text(bucket.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(BrandPalette.cream.opacity(0.65))
                        if bucket.id == store.provider.rawValue, bucket.name != "Compute poor", let plan = bucket.planType { Text(PlanLabel.format(plan)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary) }
                    }
                }.buttonStyle(.plain).help("Show \(bucket.name) on the notch")
                Spacer()
            }.font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).padding(.top, 14).padding(.bottom, 7)
            }
            if bucket.windows.isEmpty {
                Text("Quota unavailable").font(.system(size: 11)).foregroundStyle(.secondary).frame(height: 39)
            }
            ForEach(Array(store.displayWindows(bucket).enumerated()), id: \.offset) { rowIndex, window in
                VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 4) {
                        Text(window.name).font(.system(size: 13, weight: .semibold))
                        Text(store.sourceFresh ? "\(Int(window.remaining.rounded()))%" : "—")
                            .font(.custom("Menlo-Bold", size: 13))
                        Text("left").font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 6)
                        Text("Resets in \(store.countdown(window.resetDate))").font(.system(size: 11)).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .help(window.resetDate?.formatted(date: .complete, time: .shortened) ?? "Reset time unavailable")
                    }.foregroundStyle(BrandPalette.cream).matteContentShade(spread: 7)
                    GeometryReader { proxy in
                        Capsule().fill(BrandPalette.cream.opacity(0.12)).overlay(alignment: .leading) {
                            Capsule().fill(window.remaining <= 10 ? BrandPalette.sand : themeAccent)
                                .frame(width: store.sourceFresh ? proxy.size.width * window.remaining / 100 : 0)
                        }
                    }.frame(height: 5).matteContentShade(spread: 5)
                        .opacity(bucket.id == store.provider.rawValue && window.windowDurationMins == store.sharedFiveHour?.windowDurationMins ? 0 : 1)
                        .anchorPreference(key: QuotaAnchors.self, value: .bounds) { bucket.id == store.provider.rawValue && window.windowDurationMins == store.sharedFiveHour?.windowDurationMins ? ["bar": $0] : [:] }
                }.frame(height: 52)
                    .onTapGesture {
                        if bucket.id == store.provider.rawValue, window.windowDurationMins == 10080 { store.setHistoryOpen(true) }
                    }
                    .modifier(DescendingReveal(amount: IslandMotion.smooth((motion.progress - 0.46 - Double(rowIndex) * 0.10) / 0.28)))
                if bucket.id == store.provider.rawValue, window.windowDurationMins == 10080, store.weeklyHistoryOpen {
                    WeeklyHistoryView(store: store).padding(.top, 8).padding(.bottom, 8)
                        .transition(.opacity.combined(with: .offset(y: -6)))
                }
                }
                .contentShape(Rectangle())
                .onHover { inside in
                    if bucket.id == store.provider.rawValue, window.windowDurationMins == 10080 { store.hoverWeekly(inside) }
                }
                .accessibilityAction(named: "Show seven-day token history") { store.setHistoryOpen(true) }


            }
        }
    }
}
/// Fixed native drawing prevents NSMenu from adopting an image's source dimensions.
struct ProviderPicker: NSViewRepresentable {
    @ObservedObject var store: UsageStore
    func makeNSView(context: Context) -> ProviderPickerButton { ProviderPickerButton(store: store) }
    func updateNSView(_ view: ProviderPickerButton, context: Context) {
        view.store = store
        view.setAccessibilityLabel("Provider: \(store.provider.displayName)")
        view.needsDisplay = true
    }
}

final class ProviderPickerButton: NSButton {
    var store: UsageStore
    init(store: UsageStore) {
        self.store = store
        super.init(frame: NSRect(x: 0, y: 0, width: 65, height: 24))
        isBordered = false
        title = ""
        target = self
        action = #selector(showProviders)
        toolTip = "Choose Claude or Codex"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { NSSize(width: 65, height: 24) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private func mark(_ provider: UsageProvider, size: CGFloat) -> NSImage? {
        guard let url = Bundle.main.url(forResource: "ProviderIcon-" + provider.rawValue, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        return image
    }
    override func draw(_ dirtyRect: NSRect) {
        let center = bounds.midY
        // Both source marks use the same 100-unit canvas and optical padding.
        mark(store.provider, size: 16)?.draw(in: NSRect(x: 0, y: center - 8, width: 16, height: 16),
            from: .zero, operation: .sourceOver, fraction: 0.8, respectFlipped: true, hints: nil)
        let plan = store.buckets.first(where: { $0.id == store.provider.rawValue })?.planType.map(PlanLabel.format) ?? store.provider.displayName
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(BrandPalette.cream).withAlphaComponent(0.75), .paragraphStyle: style]
        let text = NSAttributedString(string: plan, attributes: attrs)
        text.draw(in: NSRect(x: 16, y: center - 7, width: 41, height: 14))
        NSColor(BrandPalette.cream).withAlphaComponent(0.55).setStroke()
        let arrow = NSBezierPath(); arrow.lineWidth = 1
        arrow.move(to: NSPoint(x: 59, y: center - 1))
        arrow.line(to: NSPoint(x: 61.5, y: center + 1.5))
        arrow.line(to: NSPoint(x: 64, y: center - 1)); arrow.stroke()
    }
    @objc private func showProviders() {
        let menu = NSMenu()
        for provider in UsageProvider.allCases {
            let item = NSMenuItem(title: provider.displayName, action: #selector(selectProvider(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = provider.rawValue
            item.image = mark(provider, size: 16)
            item.state = store.provider == provider ? .on : .off
            menu.addItem(item)
        }
        store.menuTracking = true
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY + 3), in: self)
        store.menuTracking = false
    }
    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let provider = UsageProvider(rawValue: raw) else { return }
        store.selectProvider(provider)
    }
}

private struct QuotaAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
private struct SharedQuotaLine: Shape {
    var progress: Double
    var destination: CGRect
    var closingElapsed: Double?
    var origin: CGRect
    func path(in rect: CGRect) -> Path {
        // Resting contour is replaced by a straight top line before translation.
        if progress == 0 {
            let inset: CGFloat = 2
            let radius: CGFloat = 8
            let left = origin.minX + inset, right = origin.maxX - inset
            let bottom = origin.height - inset
            var path = Path()
            path.move(to: CGPoint(x: left, y: 0))
            path.addLine(to: CGPoint(x: left, y: bottom - radius))
            path.addCurve(to: CGPoint(x: left + radius, y: bottom), control1: CGPoint(x: left, y: bottom - radius * 0.447715), control2: CGPoint(x: left + radius * 0.447715, y: bottom))
            path.addLine(to: CGPoint(x: right - radius, y: bottom))
            path.addCurve(to: CGPoint(x: right, y: bottom - radius), control1: CGPoint(x: right - radius * 0.447715, y: bottom), control2: CGPoint(x: right, y: bottom - radius * 0.447715))
            path.addLine(to: CGPoint(x: right, y: 0))
            return path
        }
        let travel = CGFloat(IslandMotion.smooth((progress - 0.18) / 0.72))
        let top = origin.height - 2
        let y = top + (destination.midY - top) * travel
        var path = Path()
        path.move(to: CGPoint(x: destination.minX, y: y))
        path.addLine(to: CGPoint(x: destination.maxX, y: y))
        return path
    }

}

private struct ExpandedTexture: View {
    var active: Bool
    var body: some View {
        MatteSurface(active: active)
            .accessibilityHidden(true)
    }
}

private struct OrganicReveal: Shape {
    var amount: Double
    var notchHeight: CGFloat
    var compactWidth: CGFloat
    var compactOffset: CGFloat
    func path(in rect: CGRect) -> Path {
        let compact = CGRect(x: compactOffset, y: 0, width: compactWidth, height: min(notchHeight, rect.height))
        var path = IslandOutline(progress: 0).path(in: CGRect(origin: .zero, size: compact.size)).applying(CGAffineTransform(translationX: compact.minX, y: 0))
        let center = CGPoint(x: rect.midX, y: notchHeight / 2)
        let radius = hypot(rect.width / 2, rect.height) * CGFloat(amount)
        var edge = Path()
        for step in 0...160 {
            let angle = CGFloat(step) / 160 * 2 * .pi
            let ripple: CGFloat = 0
            let distance = max(0, radius + ripple)
            let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
            if step == 0 { edge.move(to: point) } else { edge.addLine(to: point) }
        }
        edge.closeSubpath()
        path.addPath(edge)
        return path
    }
}

private struct DescendingReveal: ViewModifier {
    var amount: Double
    func body(content: Content) -> some View {
        content.opacity(amount)
            .blur(radius: 6 * (1 - amount))
            .offset(y: -12 * (1 - amount))
    }
}
