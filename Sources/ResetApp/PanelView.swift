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
                        ProviderPicker(store: store)
                            .frame(width: 65, height: store.notchSize.height - 7, alignment: .leading)
                        Spacer()
                        Button { store.refresh() } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10)).frame(width: 20, height: 24).matteContentShade()
                        }.buttonStyle(.plain).disabled(store.refreshing)
                            .accessibilityLabel("Refresh usage").help(store.freshness)
                        Menu {
                            Button("Rebuild dot mesh") { MatteSurfaceView.current?.rebuildMesh() }
                            Divider()
                            if store.provider == .codex { Toggle("Enable Spark", isOn: Binding(get: { store.sparkEnabled }, set: { store.setSparkEnabled($0) })) }
                            Divider()
                            ForEach(Placement.allCases, id: \.self) { placement in
                                Button { store.move(to: placement) } label: {
                                    Label(placement.rawValue, systemImage: store.placement == placement ? "checkmark" : "rectangle")
                                }
                            }
                            Divider()
                            Button("Quit ResetMe") { NSApplication.shared.terminate(nil) }
                        } label: { Image(systemName: "ellipsis").frame(width: 16, height: 24).matteContentShade() }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20, height: 24).clipped().accessibilityLabel("Placement")
                    }.foregroundStyle(.secondary).padding(.horizontal, 16).frame(height: store.notchSize.height - 7)
                    PanelView(store: store, embedded: true)
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
                    let color: Color = value == nil ? .secondary : remaining < 5 ? Color(red: 0.98, green: 0.57, blue: 0.48) : remaining < 10 ? .orange : themeAccent
                    SharedQuotaLine(progress: progress, destination: bar, closingElapsed: store.expanded ? nil : motion.closingElapsed, origin: CGRect(x: virtualNotch.minX - IslandMotion.wingWidth - surfaceFrame.minX + inset, y: 0, width: store.notchSize.width + IslandMotion.wingWidth - 2 * inset, height: store.notchSize.height - inset))
                        .stroke(Color(white: 0.30), style: StrokeStyle(lineWidth: 2.5 + 2.5 * t, lineCap: .round, lineJoin: .round))
                        .opacity(lineOpacity * emergence)
                    SharedQuotaLine(progress: progress, destination: bar, closingElapsed: store.expanded ? nil : motion.closingElapsed, origin: CGRect(x: virtualNotch.minX - IslandMotion.wingWidth - surfaceFrame.minX + inset, y: 0, width: store.notchSize.width + IslandMotion.wingWidth - 2 * inset, height: store.notchSize.height - inset))
                        .trim(from: 0, to: remaining / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 2.5 + 2.5 * t, lineCap: .round, lineJoin: .round))
                        .shadow(color: color.opacity(pulse * 0.5), radius: 3 * pulse)
                        .opacity(lineOpacity * emergence)
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
struct NotchView: View {
    @ObservedObject var store: UsageStore
    var size: CGSize? = nil
    var body: some View {
        ZStack {
            NotchContour().stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            if store.usable {
                NotchContour().trim(from: 0, to: (store.window?.remaining ?? 0) / 100)
                    .stroke(store.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            } else {
                NotchContour().stroke(.gray.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
        }
        .frame(width: size?.width ?? store.notchSize.width, height: size?.height ?? store.notchSize.height)
        .contentShape(Rectangle())
        .onTapGesture { store.setExpanded(true); store.onFocus?() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(store.selected?.name ?? store.provider.displayName), \(store.window?.name ?? "quota"), \(store.remainingText) left")
        .accessibilityValue(store.expanded ? "Expanded" : "Collapsed")
    }
}
struct PanelView: View {
    @ObservedObject private var scene = SceneSettings.shared
    @ObservedObject var store: UsageStore
    @ObservedObject var motion: IslandPresentation
    var embedded = false
    init(store: UsageStore, embedded: Bool = false) { self.store = store; self.motion = store.motion; self.embedded = embedded }
    var body: some View {
        if embedded {
            detail.preferredColorScheme(.dark).tint(themeAccent)
        } else { surface }
    }
    var surface: some View {
        Group {
            if store.expanded { detail }
            else { compact }
        }
        .background(.ultraThinMaterial)
        .background(Color(red: 0.055, green: 0.065, blue: 0.07).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: store.expanded ? 17 : 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: store.expanded ? 17 : 12).strokeBorder(.white.opacity(0.12), lineWidth: 0.6))
        .preferredColorScheme(.dark).tint(themeAccent)
        .onExitCommand { store.dismiss() }
    }
    var compact: some View {
        HStack(spacing: 9) {
            Image(systemName: "gauge.with.dots.needle.50percent").font(.system(size: 10, weight: .medium)).foregroundStyle(store.tint)
            Text(store.selected?.name == "GPT-5.3-Codex-Spark" ? "Spark" : (store.selected?.name ?? store.provider.displayName)).font(.system(size: 11, weight: .medium)).lineLimit(1)
            Text(store.remainingText).font(.custom("Menlo-Bold", size: 11)).foregroundStyle(store.tint)
        }.padding(.horizontal, 12).frame(width: 164, height: 28)
            .overlay(DragSurface(store: store, compact: true))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(store.selected?.name ?? store.provider.displayName), \(store.remainingText) left")
    }
    var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !embedded {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    ProviderPicker(store: store)
                    Color.clear.frame(minWidth: 20, maxWidth: .infinity).overlay(DragSurface(store: store))
                }.frame(height: 24)
                Text(store.freshness).font(.system(size: 10)).foregroundStyle(.secondary)
                Button { store.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11)).frame(width: 20, height: 24)
                }.buttonStyle(.plain).disabled(store.refreshing).accessibilityLabel("Refresh usage")
                Menu {
                            Button("Rebuild dot mesh") { MatteSurfaceView.current?.rebuildMesh() }
                            Divider()
                    if store.provider == .codex { Toggle("Enable Spark", isOn: Binding(get: { store.sparkEnabled }, set: { store.setSparkEnabled($0) })) }
                    Divider()
                    ForEach(Placement.allCases, id: \.self) { placement in
                        Button { store.move(to: placement) } label: { Label(placement.rawValue, systemImage: store.placement == placement ? "checkmark" : "rectangle") }
                    }
                    Divider()
                    Button("Quit ResetMe") { NSApplication.shared.terminate(nil) }
                } label: { Image(systemName: "ellipsis").frame(width: 16, height: 24).matteContentShade() }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20, height: 24).clipped().accessibilityLabel("Placement")
            }.foregroundStyle(.secondary).padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 9)
            Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5)
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.visibleBuckets.enumerated()), id: \.element.id) { index, bucket in
                        bucketRows(bucket)
                            .modifier(DescendingReveal(amount: embedded ? IslandMotion.smooth((motion.progress - 0.35 - Double(index) * 0.12) / 0.30) : 1))
                    }
                    if store.visibleBuckets.isEmpty {
                        Text(store.refreshing ? "Connecting…" : "Quota unavailable")
                            .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
                    }
                    if let error = store.error {
                        Text(error).font(.system(size: 11)).foregroundStyle(.orange.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
                    }
                    if !store.visibleBuckets.contains(where: { $0.id == store.provider.rawValue && $0.windows.contains(where: { $0.windowDurationMins == 10080 }) }) {
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
                            .modifier(DescendingReveal(amount: embedded ? IslandMotion.smooth((motion.progress - 0.82) / 0.17) : 1))
                    }

                }.padding(.horizontal, 18).padding(.bottom, 14)
            }
        }.frame(width: 348, height: store.detailHeight - (embedded ? 78 : 0))
    }
    var bankedResets: some View {
        Group {
            if store.displayedCreditDates.count == 1 {
                HStack(spacing: 8) {
                    Image(systemName: "ticket.fill").font(.system(size: 14)).foregroundStyle(themeAccent)
                    Text("1 banked reset").font(.system(size: 12, weight: .medium)).matteContentShade()
                    Spacer(minLength: 4)
                    Text("Expires in \(store.countdown(store.displayedCreditDates[0]))")
                        .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit().matteContentShade()
                        .help(store.displayedCreditDates[0]?.formatted(date: .complete, time: .shortened) ?? "Expiry unavailable")
                }.padding(.vertical, 10).padding(.horizontal, 10)
                    .background(.clear).padding(.top, 3)
            } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "ticket.fill").font(.system(size: 15)).foregroundStyle(themeAccent)
                                Text("\(store.displayedCreditDates.count) banked reset\(store.displayedCreditDates.count == 1 ? "" : "s")").font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text("Expire in").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                                ForEach(Array(store.displayedCreditDates.enumerated()), id: \.offset) { index, expiry in
                                    creditTile(index: index, expiry: expiry)
                                }
                            }
                        }.padding(10)
                            .background(.clear).padding(.top, 3)

                }
        }
    }

    func creditTile(index: Int, expiry: Date?) -> some View {
        let first = index == 0
        let label = expiry.map { $0 <= store.now ? "Expired" : store.countdown($0) } ?? "Unknown"
        let foreground: Color = first ? themeAccent : .secondary
        let background: Color = first ? themeAccent.opacity(0.09) : .white.opacity(0.035)
        return Text(label)
            .font(.custom(first ? "Menlo-Bold" : "Menlo-Regular", size: 11))
            .foregroundStyle(foreground).frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(background, in: RoundedRectangle(cornerRadius: 7))
            .help(expiry?.formatted(date: .complete, time: .shortened) ?? "Expiry unavailable")
            .accessibilityLabel("Banked reset \(index + 1), expires in \(label)")
    }
    func bucketRows(_ bucket: LimitBucket) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !embedded || bucket.id != "codex" {
            HStack(alignment: .center) {
                Button { store.selectedID = bucket.id; store.onData?() } label: {
                    HStack(spacing: 6) {
                        Image(nsImage: NSImage(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("openai.ico")) ?? NSImage())
                            .resizable().renderingMode(.template).scaledToFit().frame(width: 13, height: 13).foregroundStyle(.white.opacity(0.8)).accessibilityLabel("OpenAI")
                        Text(store.quotaTitle(bucket)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.65))
                        if bucket.id == store.provider.rawValue, store.quotaTitle(bucket) != "Compute poor", let plan = bucket.planType { Text(PlanLabel.format(plan)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary) }
                    }
                }.buttonStyle(.plain).help("Show \(bucket.name) on the notch")
                Spacer()
                if store.isSpark(bucket) {
                    Button { store.toggleSpark() } label: {
                        Image(systemName: store.sparkExpanded ? "chevron.up" : "chevron.down")
                            .frame(width: 24, height: 18)
                    }.buttonStyle(.plain).accessibilityLabel(store.sparkExpanded ? "Collapse Spark" : "Expand Spark")
                }
            }.font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).padding(.top, 14).padding(.bottom, 7)
            }
            if !store.isSpark(bucket) || store.sparkExpanded {
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
                    }.foregroundStyle(.white).matteContentShade(spread: 7)
                    GeometryReader { proxy in
                        Capsule().fill(.white.opacity(0.12)).overlay(alignment: .leading) {
                            Capsule().fill(window.remaining <= 10 ? Color.orange.opacity(0.9) : themeAccent)
                                .frame(width: store.sourceFresh ? proxy.size.width * window.remaining / 100 : 0)
                        }
                    }.frame(height: 5).matteContentShade(spread: 5)
                        .opacity(embedded && bucket.id == store.provider.rawValue && window.windowDurationMins == store.sharedFiveHour?.windowDurationMins ? 0 : 1)
                        .anchorPreference(key: QuotaAnchors.self, value: .bounds) { embedded && bucket.id == store.provider.rawValue && window.windowDurationMins == store.sharedFiveHour?.windowDurationMins ? ["bar": $0] : [:] }
                }.frame(height: 52)
                    .onTapGesture {
                        if bucket.id == store.provider.rawValue, window.windowDurationMins == 10080 { store.setHistoryOpen(true) }
                    }
                    .modifier(DescendingReveal(amount: embedded ? IslandMotion.smooth((motion.progress - 0.46 - Double(rowIndex) * 0.10) / 0.28) : 1))
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
}
/// Native menu keeps provider switching accessible without making the notch a key window.
struct ProviderPicker: View {
    @ObservedObject var store: UsageStore
    private var plan: String {
        store.buckets.first(where: { $0.id == store.provider.rawValue })?.planType.map(PlanLabel.format) ?? store.provider.displayName
    }
    var body: some View {
        Menu {
            ForEach(UsageProvider.allCases) { provider in
                Button { store.selectProvider(provider) } label: {
                    Label(provider.displayName, systemImage: store.provider == provider ? "checkmark" : "circle")
                }
            }
        } label: {
            HStack(spacing: 5) {
                if store.provider == .codex {
                    Image(nsImage: Bundle.main.resourceURL.flatMap { NSImage(contentsOf: $0.appendingPathComponent("openai.ico")) } ?? NSImage())
                        .resizable().renderingMode(.template).scaledToFit().frame(width: 12, height: 12)
                } else {
                    Image(systemName: "sun.max.fill").font(.system(size: 12)).foregroundStyle(Color(red: 0.84, green: 0.57, blue: 0.43))
                }
                Text(plan).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
            }.foregroundStyle(.white.opacity(0.75)).matteContentShade()
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .frame(width: 65).accessibilityLabel("Provider: \(store.provider.displayName)")
        .help("Choose Claude or Codex")
    }
}

struct DragSurface: NSViewRepresentable {
    var store: UsageStore
    var compact = false
    func makeNSView(context: Context) -> DragView { let view = DragView(); view.store = store; view.compact = compact; return view }
    func updateNSView(_ nsView: DragView, context: Context) {}
}
final class DragView: NSView {
    weak var store: UsageStore?
    var compact = false
    private var dragOrigin = NSPoint.zero
    private var mouseOrigin = NSPoint.zero
    private var moved = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragOrigin = window.frame.origin; mouseOrigin = window.convertPoint(toScreen: event.locationInWindow); moved = false
        store?.isDragging = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let dx = point.x - mouseOrigin.x, dy = point.y - mouseOrigin.y
        if hypot(dx, dy) > 3 { moved = true }
        if moved { window.setFrameOrigin(NSPoint(x: dragOrigin.x + dx, y: dragOrigin.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        store?.isDragging = false
        if moved {
            store?.placement = .floating
            UserDefaults.standard.set(Placement.floating.rawValue, forKey: "placement")
            NotificationCenter.default.post(name: .resetPanelDragged, object: window)
        } else if compact { store?.setExpanded(true) }
    }
}
extension Notification.Name { static let resetPanelDragged = Notification.Name("resetPanelDragged") }

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
