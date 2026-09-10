import SwiftUI
import ResetCore

private enum HistoryMetric: String, CaseIterable { case cost = "Cost", tokens = "Tokens" }
struct WeeklyHistoryView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var scene = SceneSettings.shared
    @State private var selected: Date?
    private let extended = true
    @State private var detailIntent: Task<Void, Never>?
    @State private var detailDay: TokenDay?
    @State private var resetHovered = false
    @State private var hoveredResetDay: ResetDay?
    @State private var docking = false
    @State private var dockFrame: CGRect?
    @State private var dockTask: Task<Void, Never>?
    @State private var pointer: CGPoint?
    @State private var metric = HistoryMetric.cost
    private var accent: Color { scene.color("accent") }
    private let hoverAccent = Color(red: 0.65, green: 0.58, blue: 0.46)
    private var visibleCount: Int { extended ? 14 : 7 }
    private var firstIndex: Int { max(0, store.tokenDays.count - visibleCount) }
    private var selectedDay: TokenDay? { store.tokenDays.first { $0.date == selected } ?? store.pinnedDay ?? store.tokenDays.last }
    private var motion: Animation? { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.9) }
    private var numberMotion: Animation? { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.16) }
    private func value(_ day: TokenDay) -> Double? { metric == .cost ? day.cost : day.tokens.map(Double.init) }
    private var weekDays: [TokenDay] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date()))!
        return store.tokenDays.filter { $0.date >= start && $0.date <= Date() }
    }
    private var readout: String {
        let amounts = weekDays.compactMap { value($0) }
        guard !amounts.isEmpty else { return "—" }
        let amount = amounts.reduce(0, +)
        return metric == .cost ? amount.formatted(.currency(code: "USD").precision(.fractionLength(0))) : amount.formatted(.number.notation(.compactName).precision(.fractionLength(amount < 10_000_000 ? 1 : 0)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(readout).font(.custom("Menlo-Bold", size: 21)).foregroundStyle(accent).matteContentShade(spread: 8)
                    .contentTransition(.numericText())
                    .animation(numberMotion, value: readout)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("7d")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                if extended { Text("14d").font(.system(size: 9)).foregroundStyle(.secondary) }
                if store.provider == .claude {
                    Text("Tokens").font(.system(size: 10)).foregroundStyle(.secondary)
                        .help("Local Claude token counts. Cost estimates are unavailable.")
                } else { Picker("History metric", selection: $metric) {
                    ForEach(HistoryMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).labelsHidden().controlSize(.mini).fixedSize()
                    .tint(accent).accessibilityLabel("History metric") }
            }
            .help("7d: today and the preceding six calendar days, local time. Chart: last 14 days. Local usage; costs are partial API estimates. Hover a bar for its day; click to dock details.")
            chart.frame(height: 76).padding(.leading, -18).padding(.trailing, 4)
            if let day = store.pinnedDay {
                Rectangle().fill(LinearGradient(colors: [.clear, .white.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 0.5).padding(.vertical, 7).allowsHitTesting(false)
                DayDetailCard(day: day, expanded: store.dayDetailsExpanded, close: store.closeDay)
                    .frame(height: max(0, store.dayCardHeight - 24), alignment: .top).clipped()
                    .background(DayDockTarget { frame in if dockFrame != frame { dockFrame = frame } })
                    .opacity(docking ? 0 : 1).padding(.top, 3)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }

        }
        .padding(.top, 3).padding(.bottom, 4)

        .animation(motion, value: store.dayCardHeight)
        .onAppear { if store.provider == .claude { metric = .tokens } }
        .onChange(of: store.provider) { metric = store.provider == .claude ? .tokens : .cost; resetHovered = false; hoveredResetDay = nil }
        .onDisappear { detailIntent?.cancel(); dockTask?.cancel(); docking = false; detailDay = nil }
    }
    private struct ResetPosition: Identifiable {
        var group: ResetDay
        var x: CGFloat
        var id: Date { group.id }
    }
    private struct ChartLayout {
        var centers: [CGFloat]
        var markers: [ResetPosition]
    }
    private func resetLayout(width: CGFloat, barWidth: CGFloat) -> ChartLayout {
        let groups = resetDays
        let first = store.tokenDays.dropFirst(firstIndex).first?.date
        let indices: [Int] = groups.map { group in
            guard let first else { return -1 }
            return Calendar.current.dateComponents([.day], from: first, to: group.date).day ?? -1
        }
        let boundaries = Set(indices.filter { $0 > 0 && $0 < visibleCount })
        let resetGap: CGFloat = boundaries.isEmpty ? 0 : min(CGFloat(scene["resetGap"]), width * 0.22 / CGFloat(boundaries.count))
        let step: CGFloat = max(0, width - barWidth - resetGap * CGFloat(boundaries.count)) / CGFloat(visibleCount - 1)
        var centers: [CGFloat] = []
        for index in 0..<visibleCount {
            let offset = CGFloat(boundaries.filter { $0 <= index }.count) * resetGap
            centers.append(CGFloat(index) * step + barWidth * 0.5 + offset)
        }
        var markers: [ResetPosition] = []
        for (group, index) in zip(groups, indices) where index >= 0 && index < visibleCount {
            let x: CGFloat
            if index == 0 { x = max(CGFloat(scene["resetSize"]) * 0.5, centers[0] - barWidth * 0.5) }
            else { x = (centers[index - 1] + centers[index]) * 0.5 }
            markers.append(ResetPosition(group: group, x: x))
        }
        return ChartLayout(centers: centers, markers: markers)
    }
    private var chart: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let barWidth: CGFloat = scene["barWidth"]
            let layout = resetLayout(width: width, barWidth: barWidth)
            let step = max(1, (width - barWidth) / CGFloat(visibleCount - 1))
            let centers = layout.centers
            let markers = layout.markers
            let maximum = max(1, store.tokenDays.compactMap { value($0) }.max() ?? 1)
            ZStack(alignment: .topLeading) {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(scene["chartShade"]*0.4), location: 0.3), .init(color: .black.opacity(scene["chartShade"]*0.82), location: 0.76), .init(color: .black.opacity(scene["chartShade"]), location: 1)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
                if let pointer {
                    RadialGradient(colors: [accent.opacity(scene["glow"]*4.375), accent.opacity(scene["glow"]*1.25), .clear], center: .center, startRadius: 0, endRadius: 58)
                        .frame(width: 116, height: 116).position(x: pointer.x, y: min(66, max(14, pointer.y)))
                        .blur(radius: 9).allowsHitTesting(false)
                }
                if let selected, let index = store.tokenDays.firstIndex(where: { $0.date == selected }), index >= firstIndex {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(LinearGradient(colors: [hoverAccent.opacity(scene["selection"]), hoverAccent.opacity(0.065)], startPoint: .top, endPoint: .bottom))
                        .frame(width: min(step - 2, barWidth + 4), height: 66)
                        .blur(radius: 2.5)
                        .shadow(color: hoverAccent.opacity(0.1), radius: 5)
                        .position(x: centers[min(visibleCount - 1, index - firstIndex)], y: 37)
                        .animation(numberMotion, value: selected)
                        .allowsHitTesting(false)
                }
                ForEach(Array(store.tokenDays.enumerated()), id: \.element.id) { index, day in
                    let position = index - firstIndex
                    let latest = index == store.tokenDays.count - 1
                    let height = value(day).map { max(3, scene["barHeight"] * $0 / maximum) } ?? 2
                    RevealingHistoryBar(height: height, width: barWidth, radius: scene["barRadius"],
                        index: max(0, position), emphasized: latest || selected == day.date,
                        hasData: value(day) != nil)
                        .overlay {
                            if selected == day.date {
                                HoverStripes().clipShape(RoundedRectangle(cornerRadius: scene["barRadius"]))
                                    .allowsHitTesting(false)
                            }
                        }
                        .shadow(color: accent.opacity(0.16), radius: 3, y: 2)
                        .opacity(value(day) == nil ? 0.15 : 1)
                        .position(x: position >= 0 && position < visibleCount ? centers[position] : -barWidth, y: 72 - height / 2)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(latest ? "Today" : day.date.formatted(date: .abbreviated, time: .omitted)), \(day.tokens.map { "\($0) local tokens" } ?? "unavailable")")
                        .accessibilityHidden(index < firstIndex)
                        .accessibilityAction(named: "Open day details") { store.pinDay(day) }
                }
                ForEach(markers) { marker in
                    ResetBoundaryMarker(count: marker.group.events.count)
                        .position(x: marker.x, y: 36)
                        .help("\(marker.group.events.count) weekly reset(s) · \(marker.group.date.formatted(date: .abbreviated, time: .omitted))")
                }
                if store.historyLoading && store.tokenDays.isEmpty {
                    Text("Loading history").font(.system(size: 9)).foregroundStyle(.secondary).position(x: width / 2, y: 36)
                }
            }.frame(width: width, height: 76).clipped().contentShape(Rectangle())
                .background(HistoryHoverPanel(point: pointer, content: resetHovered ? resetHoverContent : ((store.pinnedDay == nil || docking) ? detailDay.map { AnyView(DayDetailCard(day: $0, expanded: false, close: {}, showClickHint: true)) } : nil), cardHeight: resetHovered ? resetHoverHeight : 100, cardWidth: resetHovered ? resetHoverWidth : 140, docking: docking, dockFrame: dockFrame, onDocked: finishDock).allowsHitTesting(false))
                .overlay(ChartPressSurface(pressed: { location in
                    if let marker = markers.min(by: { abs($0.x - location.x) < abs($1.x - location.x) }), abs(marker.x - location.x) < 8 {
                        return
                    }
                    let nearest = centers.indices.min(by: { abs(centers[$0]-location.x) < abs(centers[$1]-location.x) }) ?? 0
                    let index = firstIndex + nearest
                    guard store.tokenDays.indices.contains(index) else { return }
                    dock(store.tokenDays[index])
                }, hovered: { location in
                    guard let location else {
                        pointer = nil; selected = nil; detailDay = nil; resetHovered = false; return
                    }
                    pointer = location
                    if let marker = markers.min(by: { abs($0.x - location.x) < abs($1.x - location.x) }), abs(marker.x - location.x) < 8 {
                        hoveredResetDay = marker.group; resetHovered = true; selected = nil; detailDay = nil; return
                    }
                    resetHovered = false
                    let nearest = centers.indices.min(by: { abs(centers[$0]-location.x) < abs(centers[$1]-location.x) }) ?? 0
                    let index = firstIndex + nearest
                    guard store.tokenDays.indices.contains(index) else { return }
                    let day = store.tokenDays[index]
                    guard selected != day.date else { return }
                    selected = day.date
                    if store.pinnedDay != nil { detailDay = nil; store.pinnedDay = day }
                    else { detailDay = day }
                }))
        }
    }
    private var resetHoverWidth: CGFloat {
        hoveredResetDay?.events.contains(where: { $0.kind == .scheduled }) == true ? 156 : 124
    }
    private var resetHoverHeight: CGFloat {
        let count = hoveredResetDay?.events.count ?? 1
        return CGFloat(count * 30 + (count > 1 ? 22 : 10))
    }
    private var resetHoverContent: AnyView? {
        guard let group = hoveredResetDay else { return nil }
        return AnyView(VStack(alignment: .leading, spacing: 6) {
            if group.events.count > 1 {
                Text("\(group.events.count) weekly resets").font(.system(size: 10, weight: .semibold))
            }
            ForEach(group.events) { event in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise.circle.fill").foregroundStyle(.green)
                        Text(event.kind == .scheduled ? "Scheduled weekly reset" : "Reset")
                            .fontWeight(.semibold)
                    }.font(.system(size: 10))
                    Text(event.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.045)))
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.09), lineWidth: 0.5) })
    }
    private func dock(_ day: TokenDay) {
        detailIntent?.cancel(); dockTask?.cancel()
        detailDay = nil; docking = false; dockFrame = nil
        store.pinDay(day)
    }
    private func finishDock() {
        guard docking, let day = store.pinnedDay else { return }
        detailDay = nil; docking = false
        store.pinDay(day)
    }

    private func dateLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "en_GB")))
    }
    private func detail(_ day: TokenDay) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(dateLabel(day.date)).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text(metric == .cost ? day.cost.map { $0.formatted(.currency(code: "USD").precision(.fractionLength(0))) } ?? "—" : day.tokens.map { $0.formatted(.number.notation(.compactName).precision(.fractionLength(1))) } ?? "—").font(.custom("Menlo-Bold", size: 15)).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.75)
            }.padding(.bottom, 5)
            detailRow("in", icon: "arrow.down.left", tokens: day.uncached, cost: day.cost == nil ? nil : day.inputCost)
            detailRow("cached", icon: "memorychip", tokens: day.cached, cost: day.cost == nil ? nil : day.cachedCost)
            detailRow("out", icon: "arrow.up.right", tokens: day.output, cost: day.cost == nil ? nil : day.outputCost)
            if metric == .cost, day.unpriced > 0 {
                Text("∅ \(day.unpriced.formatted(.number.notation(.compactName).precision(.fractionLength(1)))) unpriced")
                    .font(.system(size: 8)).foregroundStyle(.secondary).padding(.top, 1)
            }
        }.padding(10).frame(width: 174).background(Color(white: 0.035))
    }
    private func detailRow(_ title: String, icon: String, tokens: Int, cost: Double?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 9)).frame(width: 12).foregroundStyle(.white.opacity(0.35))
            Text(title).font(.custom("Menlo", size: 10)).foregroundStyle(.secondary)
            Spacer()
            Text(metric == .tokens ? tokens.formatted(.number.notation(.compactName).precision(.fractionLength(2))) : cost.map { $0.formatted(.currency(code: "USD").precision(.fractionLength(0))) } ?? "—")
                .font(.custom("Menlo", size: 10)).foregroundStyle(.white.opacity(0.6))
        }
        .accessibilityLabel("\(title == "in" ? "Uncached input" : title == "cached" ? "Cached input" : "Output"), \(tokens) tokens")
    }
    private var resetDays: [ResetDay] {
        guard let start = store.tokenDays.dropFirst(firstIndex).first?.date,
              let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: store.now)) else { return [] }
        return ResetDay.groups(store.resetHistory.events, provider: store.provider, start: start, end: end)
    }
}


private struct ResetBoundaryMarker: View {
    var count: Int
    @ObservedObject private var scene = SceneSettings.shared
    private var green: Color { scene.color("reset") }
    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(LinearGradient(colors: [green.opacity(0.85), green.opacity(0.65), green], startPoint: .leading, endPoint: .trailing))
                .frame(width: scene["resetWidth"], height: 72-scene["resetSize"]+3)
                .overlay(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.5)).frame(width: 0.5).padding(.vertical, 1)
                }
                .offset(y: scene["resetSize"]-3)
            Group {
                if count > 1 { Text(count > 9 ? "9+" : String(count)) }
                else { Image(systemName: "arrow.clockwise") }
            }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.black.opacity(0.8))
                .frame(width: scene["resetSize"], height: scene["resetSize"])
                .background {
                    Circle().fill(LinearGradient(colors: [green.opacity(0.75), green], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5) }
        }
        .frame(width: scene["resetSize"], height: 72, alignment: .top)
        .accessibilityLabel("\(count) quota reset\(count == 1 ? "" : "s")")
    }
}


/// Each mounted chart plays once; late data starts growth when it becomes available.
private struct RevealingHistoryBar: View {
    let height: CGFloat
    let width: CGFloat
    let radius: CGFloat
    let index: Int
    let emphasized: Bool
    let hasData: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    var body: some View {
        PhysicalGlassBar(emphasized: emphasized)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .frame(width: width, height: height)
            .scaleEffect(x: 1, y: revealed || reduceMotion ? 1 : 0.025, anchor: .bottom)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.38).delay(Double(index)*0.018), value: revealed)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: height)
            .task(id: hasData) {
                guard hasData else { revealed = false; return }
                // Let the baseline render before revealing cached or newly loaded bars.
                try? await Task.sleep(nanoseconds: 30_000_000)
                guard !Task.isCancelled else { return }
                revealed = true
            }
    }
}

private struct ChartPressSurface: NSViewRepresentable {
    var pressed: (CGPoint) -> Void
    var hovered: (CGPoint?) -> Void
    func makeNSView(context: Context) -> ChartPressView { let view = ChartPressView(); view.pressed = pressed; view.hovered = hovered; return view }
    func updateNSView(_ view: ChartPressView, context: Context) { view.pressed = pressed; view.hovered = hovered }
}
private final class ChartPressView: NSView {
    var pressed: ((CGPoint) -> Void)?
    var hovered: ((CGPoint?) -> Void)?
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseMoved(with event: NSEvent) { hovered?(convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { hovered?(nil) }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { pressed?(convert(event.locationInWindow, from: nil)) }
}
