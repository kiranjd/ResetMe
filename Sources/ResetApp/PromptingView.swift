import SwiftUI
import ResetCore

@MainActor final class PromptingStore: ObservableObject {
    @Published private(set) var snapshot: PromptingSnapshot?
    @Published private(set) var loading = false
    @Published var dayOffset = 0
    @Published var contextLabels = UserDefaults.standard.dictionary(forKey: "promptingContextLabelsV1") as? [String: String] ?? [:]
    var contextHours: [ContextHour] {
        guard let snapshot, let day else { return [] }
        return ContextMetrics.hours(messages: snapshot.contextMessages, tasks: snapshot.contextTasks, day: day.date, overrides: contextLabels)
    }
    private let reader = PromptingHistory()
    private var task: Task<Void, Never>?
    var day: PromptingDay? { snapshot?.days.reversed().dropFirst(dayOffset).first }
    func refresh() {
        guard task == nil else { return }
        loading = true
        task = Task(priority: .userInitiated) { [weak self, reader] in
            let snapshot = await reader.read()
            guard let self, !Task.isCancelled else { return }
            self.snapshot = snapshot; self.loading = false; self.task = nil
        }
    }
    func refreshIfNeeded() {
        if snapshot == nil || Date().timeIntervalSince(snapshot!.updatedAt) >= 60 { refresh() }
    }
}

struct PromptingView: View {
    @ObservedObject var store: PromptingStore
    private var day: PromptingDay? { store.day }
    private var screenTimeBlocked: Bool { store.snapshot?.screenTimeAccessDenied == true }
    private var contextValue: String {
        if let average = ContextMetrics.average(store.contextHours) { return average.formatted(.number.precision(.fractionLength(0...1))) }
        return (day?.prompts ?? 0) > 0 ? "≥1" : "—"
    }
    private var contextExplanation: String {
        if ContextMetrics.average(store.contextHours) == nil, (day?.prompts ?? 0) > 0 {
            return "Prompts confirm at least one context. Context labels are incomplete, so ≥1 is a lower bound, not a measured hourly average."
        }
        let hours = store.contextHours
        let classified = hours.filter { $0.unclassified == 0 }.count
        if hours.isEmpty { return "No eligible prompts recorded; agent-created and unknown-origin tasks are excluded." }
        if classified == 0 { return "Context labels are unavailable for these tasks; unclassified hours do not count as zero." }
        return "Average contexts across \(classified) prompt hours in user-created tasks; \(hours.count - classified) unclassified hours excluded."
    }
    private var dateTitle: String {
        if store.dayOffset == 0 { return "Today" }
        if store.dayOffset == 1 { return "Yesterday" }
        return day?.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? "Earlier"
    }
    private func time(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        let minutes = Int(seconds / 60)
        if seconds > 0 && minutes == 0 { return "<1m" }
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { store.dayOffset = 0 } label: {
                    Text(dateTitle).font(.system(size: 12, weight: .medium)).frame(height: 28)
                }.buttonStyle(.plain).help("Return to today")
                Spacer()
                dayButton("chevron.left", label: "Previous day", disabled: store.dayOffset >= 6) { store.dayOffset += 1 }
                dayButton("chevron.right", label: "Next day", disabled: store.dayOffset == 0) { store.dayOffset -= 1 }
            }
            HStack(alignment: .center, spacing: 12) {
                Text(time(day?.codexSeconds)).font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                PromptingIcon(symbol: .time, size: 32)
                Text(screenTimeBlocked ? "Screen Time\naccess needed" : "Active in\nCodex").font(.system(size: 12, weight: .medium)).foregroundStyle(BrandPalette.cream.opacity(0.72)).fixedSize()
            }.frame(height: 74)
                .modifier(PromptingExplanation(copy: store.loading && store.snapshot == nil ? "Reading your local activity history." : screenTimeBlocked ? "Enable ResetMe in System Settings → Privacy & Security → Full Disk Access, then relaunch the app." : day?.codexSeconds == nil ? "Screen Time history for this Mac is unavailable for this day." : "Time Codex was in the foreground on this Mac, from recorded Screen Time focus intervals."))
                .accessibilityElement(children: .contain).accessibilityLabel("Codex foreground time").accessibilityValue(time(day?.codexSeconds))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    metric("Contexts / hour", icon: .tasks, value: contextValue, explanation: contextExplanation)
                    columnRule
                metric("Parallel sessions", icon: .parallel, value: day?.parallelShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", explanation: day?.parallelShare == nil ? "No completed session-running time is available to calculate a percentage." : "Share of recorded session-running time with two or more tasks running together. Excludes agent-created tasks, subagents and unfinished turns; not a share of Screen Time.")
                }
                Rectangle().fill(BrandPalette.cream.opacity(0.12)).frame(height: 1)
                HStack(spacing: 0) {
                    metric("Total prompts", icon: .prompts, value: day?.prompts.map(String.init) ?? "—", explanation: day?.prompts == nil ? "Local prompt history is unavailable for this day." : "Recorded prompts in user-created tasks, excluding identifiable automation; message authorship is not always verifiable.")
                    columnRule
                    metric("Top task share", icon: .focus, value: day?.topTaskShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", explanation: day?.topTaskShare == nil ? "No recorded prompts are available to calculate a top-task share." : "The percentage of your recorded prompts that went to your most-prompted task.")
                }
            }
            .background(BrandPalette.forest.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BrandPalette.cream.opacity(0.12), lineWidth: 1))
            Spacer(minLength: 0)
        }
        .foregroundStyle(BrandPalette.cream)
        .padding(.horizontal, 22).padding(.bottom, 16)
        .frame(width: 348, height: 300)
        .accessibilityElement(children: .contain)
        .task { store.refreshIfNeeded() }
    }
    private func dayButton(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 28, height: 28).contentShape(Rectangle()) }
            .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.25 : 0.8).accessibilityLabel(label).help(label)
    }
    private var columnRule: some View {
        Rectangle().fill(BrandPalette.cream.opacity(0.16)).frame(width: 1, height: 88)
    }
    private func metric(_ title: String, icon: PromptingSymbol, value: String, explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(BrandPalette.cream.opacity(0.68))
            HStack(alignment: .center) {
                Text(value).font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                PromptingIcon(symbol: icon, size: 32)
            }
        }.padding(.horizontal, 13).frame(maxWidth: .infinity, alignment: .leading).frame(height: 88)
            .modifier(PromptingExplanation(copy: store.loading && store.snapshot == nil ? "Reading your local history." : explanation))
            .accessibilityElement(children: .contain).accessibilityLabel(title).accessibilityValue(value).accessibilityHint(explanation)
    }
}

/// Uses the same pointer-transparent floating panel as the quota history cards.
private struct PromptingExplanation: ViewModifier {
    let copy: String
    @State private var pointer: CGPoint?
    func body(content: Content) -> some View {
        content.contentShape(Rectangle()).accessibilityHint(copy)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): pointer = location
                case .ended: pointer = nil
                }
            }
            .background(HistoryHoverPanel(point: pointer, content: pointer == nil ? nil : AnyView(
                Text(copy).font(.system(size: 11)).lineSpacing(3)
                    .foregroundStyle(BrandPalette.cream.opacity(0.88))
                    .padding(11).frame(width: 224, height: 72, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.045)))
            ), cardHeight: 72, cardWidth: 224).allowsHitTesting(false))
            .onDisappear { pointer = nil }
    }
}
