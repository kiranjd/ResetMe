import SwiftUI
import ResetCore

struct DayDetailCard: View {
    @ObservedObject private var scene = SceneSettings.shared
    @State private var hovered: Int?
    @State private var revealed = false
    let day: TokenDay
    let expanded: Bool
    let close: () -> Void
    var showClickHint = false
    private var accent: Color { scene.color("accent") }
    private func money(_ amount: Double?) -> String { amount.map { $0.formatted(.currency(code: "USD").precision(.fractionLength($0 < 10 ? 2 : 0))) } ?? "—" }
    private func tokens(_ count: Int?) -> String { count.map { $0.formatted(.number.notation(.compactName).precision(.fractionLength($0 < 10_000_000 ? 1 : 0))) } ?? "—" }
    private var dateLabel: String {
        if Calendar.current.isDateInToday(day.date) { return "Today" }
        if Calendar.current.isDateInYesterday(day.date) { return "Yesterday" }
        return day.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "en_GB")))
    }
    private var costs: [Double] { [max(0, day.inputCost), max(0, day.cachedCost), max(0, day.outputCost)] }
    private var shares: [Double] { day.cost == nil ? counts.map(Double.init) : costs }
    private func partReadout(_ index: Int) -> String {
        day.cost == nil ? "\(tokens(counts[index])) tok" : "\(money(costs[index])) · \(tokens(counts[index])) tok"
    }
    private var names: [String] { ["Uncached input", "Cached input", "Output"] }
    private var counts: [Int] { [day.uncached, day.cached, day.output] }
    private var icons: [String] { ["arrow.down", "arrow.triangle.2.circlepath", "arrow.up"] }
    private func disclosure(_ index: Int) -> String {
        "\(names[index]) · \(tokens(counts[index])) tokens · \(money(day.cost == nil ? nil : costs[index]))"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 10 : 6) {
            if expanded {
                HStack(spacing: 7) {
                    Text(dateLabel).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.secondary)
                    if day.cost != nil { totalCost }
                    Text("\(tokens(day.tokens)) tok").contentTransition(.numericText()).animation(numberMotion, value: day.tokens).font(.custom("Menlo-Bold", size: 16)).foregroundStyle(BrandPalette.cream.opacity(0.85))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Text(day.topModel ?? "Model unavailable")
                        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                        .help("Top model by attributable tokens for this day")
                }.matteContentShade(spread: 3).modifier(DayReveal(visible: revealed, delay: 0))
            } else {
                Text(dateLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                totalCost
                Text("\(tokens(day.tokens)) tokens").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            if showClickHint {
                Label("Click for details", systemImage: "arrow.up.right")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }
            if expanded {
                GeometryReader { geometry in
                    let sum = shares.reduce(0, +)
                    let available = max(0, geometry.size.width-6)
                    let widths = shares.map { sum > 0 ? available*$0/sum : available/3 }
                    VStack(spacing: 7) {
                        HStack(spacing: 6) {
                            HStack(spacing: 0) {
                                segment(0, width: widths[0])
                                segment(1, width: widths[1])
                            }.clipShape(RoundedRectangle(cornerRadius: 5))
                            segment(2, width: widths[2]).clipShape(RoundedRectangle(cornerRadius: 5))
                        }.frame(height: 30).modifier(DayReveal(visible: revealed, delay: 0.06))
                        ZStack(alignment: .topLeading) {
                            ForEach(0..<3) { index in
                                let active = hovered == index && widths[index] < 100
                                let slot: CGFloat = active ? min(150, geometry.size.width) : 62
                                let center = index == 0 ? slot/2 : index == 2 ? geometry.size.width-slot/2 : widths[0]+widths[1]/2
                                let otherActive = hovered.map { $0 != index && widths[$0] < 100 } ?? false
                                Text(active ? partReadout(index) : ["Uncached", "Cached", "Output"][index])
                                    .font(.system(size: 10, weight: .medium, design: active ? .monospaced : .default))
                                    .foregroundStyle(active ? partColor(index) : .secondary)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                                    .frame(width: slot, alignment: index == 0 ? .leading : index == 2 ? .trailing : .center)
                                    .contentShape(Rectangle())
                                    .onHover { inside in
                                        if inside { hovered = index }
                                        else if hovered == index { hovered = nil }
                                    }
                                    .position(x: min(geometry.size.width-slot/2,max(slot/2,center)), y: 7)
                                    .opacity(otherActive ? 0 : 1)
                                    .allowsHitTesting(!otherActive)
                            }
                        }.frame(height: 14).modifier(DayReveal(visible: revealed, delay: 0.12))
                    }
                }.frame(height: 57).animation(numberMotion, value: shares)
            }
        }.padding(expanded ? 4 : 9)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                if !expanded { RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.045)) }
            }
            .onChange(of: day.date) { hovered = nil }
            .task {
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { revealed = false }
                try? await Task.sleep(nanoseconds: 20_000_000)
                guard !Task.isCancelled else { return }
                revealed = true
            }

    }
    private var numberMotion: Animation? { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeInOut(duration: 0.20) }
    private var totalCost: some View {
        Text(money(day.cost)).font(.custom("Menlo-Bold", size: expanded ? 16 : 18))
            .foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.75)
            .contentTransition(.numericText()).animation(numberMotion, value: day.cost)
    }
    private func partColor(_ index: Int) -> Color {
        [BrandPalette.sand, BrandPalette.cream, BrandPalette.copper][index]
    }
    private func segment(_ index: Int, width: CGFloat) -> some View {
        let color = partColor(index)
        return Rectangle()
            .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.45), color.opacity(0.8)], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(BrandPalette.cream.opacity(0.55)).frame(height: 0.7) }
            .overlay(alignment: .trailing) { if index == 0 { Rectangle().fill(.black.opacity(0.45)).frame(width: 1) } }
            .overlay {
                if width >= 100 {
                    HStack(spacing: 7) {
                        if day.cost != nil { Text(money(costs[index])).contentTransition(.numericText()) }
                        Text("\(tokens(counts[index])) tok").contentTransition(.numericText())
                    }.font(.custom("Menlo-Bold", size: 10)).foregroundStyle(BrandPalette.cream).lineLimit(1)
                } else if width >= 18 {
                    Text(day.cost == nil ? "\(tokens(counts[index])) tok" : money(costs[index])).contentTransition(.numericText())
                        .font(.custom("Menlo-Bold", size: 10)).foregroundStyle(BrandPalette.cream)
                        .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 1)
                }
            }
            .overlay {
                if hovered == index {
                    HoverStripes().allowsHitTesting(false)
                }
            }
            .frame(width: width).contentShape(Rectangle())
            .onHover { hovered = $0 ? index : nil }
            .accessibilityLabel(disclosure(index))
    }
}

struct HoverStripes: View {
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reducedMotion)) { timeline in
            Canvas { context, size in
                let period = 18.0
                let phase = reducedMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.2) / 1.2 * period
                context.addFilter(.blur(radius: 0.65))
                for offset in stride(from: -Double(size.height) - period,
                                     through: Double(size.width) + Double(size.height) + period,
                                     by: period) {
                    var path = Path()
                    path.move(to: CGPoint(x: offset + phase, y: -2))
                    path.addLine(to: CGPoint(x: offset + phase + 7, y: -2))
                    path.addLine(to: CGPoint(x: offset + phase + 3 - Double(size.height), y: size.height + 2))
                    path.addLine(to: CGPoint(x: offset + phase - 4 - Double(size.height), y: size.height + 2))
                    path.closeSubpath()
                    context.fill(path, with: .color(.white.opacity(0.22)))
                }
            }.clipped()
        }.allowsHitTesting(false)
    }
}

private struct DayReveal: ViewModifier {
    let visible: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduced
    func body(content: Content) -> some View {
        content.opacity(visible || reduced ? 1 : 0)
            .offset(y: visible || reduced ? 0 : 5)
            .scaleEffect(x: 1, y: visible || reduced ? 1 : 0.85, anchor: .bottom)
            .animation(reduced ? nil : .easeOut(duration: 0.24).delay(delay), value: visible)
    }
}
