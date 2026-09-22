import Foundation

public struct PromptingInput: Sendable {
    public var at: Date
    public var isCodex: Bool
    public init(at: Date, isCodex: Bool) { self.at = at; self.isCodex = isCodex }
}
public struct PromptingSelection: Sendable {
    public var at: Date
    public var task: String
    public init(at: Date, task: String) { self.at = at; self.task = task }
}
public struct PromptingMessage: Sendable {
    public var at: Date
    public var task: String
    public init(at: Date, task: String) { self.at = at; self.task = task }
}
public struct PromptingRun: Sendable {
    public var start: Date
    public var end: Date
    public var task: String
    public init(start: Date, end: Date, task: String) { self.start = start; self.end = end; self.task = task }
}
public struct PromptingDay: Identifiable, Sendable {
    public var date: Date
    public var id: Date { date }
    public var codexSeconds: Double?
    public var switchesPerHour: Double?
    public var tasksPerHour: Double?
    public var prompts: Int?
    public var topTaskShare: Double?
    public var parallelSeconds: Double?
    public var sessionSeconds: Double?
    public var parallelShare: Double? {
        guard let parallelSeconds, let sessionSeconds, sessionSeconds > 0 else { return nil }
        return parallelSeconds / sessionSeconds
    }
    public var eligibleHours = 0
    public var activityStart: Date?
    public var activityEnd: Date?
    public init(date: Date) { self.date = date }
}
public enum PromptingMetrics {
    /// Rates are medians of recorded switches in hours with a pair of selections no more than ten minutes apart.
    /// Time bridges adjacent input only up to two minutes, with Codex at both ends.
    public static func days(inputs: [PromptingInput], selections: [PromptingSelection], messages: [PromptingMessage], runs: [PromptingRun], activityRange: ClosedRange<Date>?, activityDates: [Date]? = nil, sessionsAvailable: Bool, now: Date, calendar: Calendar = .current, count: Int = 7) -> [PromptingDay] {
        let today = calendar.startOfDay(for: now)
        var days = (0..<max(1, count)).reversed().map { PromptingDay(date: calendar.date(byAdding: .day, value: -$0, to: today)!) }
        let index = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($0.element.date, $0.offset) })
        func dayIndex(_ date: Date) -> Int? { index[calendar.startOfDay(for: date)] }
        func distribute(_ a: Date, _ b: Date, _ apply: (Int, Double) -> Void) {
            var at = max(a, days[0].date)
            let end = min(b, now)
            while at < end {
                let next = min(end, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: at))!)
                if let i = dayIndex(at) { apply(i, next.timeIntervalSince(at)) }
                at = next
            }
        }
        let observedDays = activityDates.map { Set($0.map { calendar.startOfDay(for: $0) }) }
        for i in days.indices {
            let end = min(now, calendar.date(byAdding: .day, value: 1, to: days[i].date)!)
            if let range = activityRange, range.lowerBound < end, range.upperBound >= days[i].date, observedDays?.contains(days[i].date) != false {
                days[i].codexSeconds = 0
                days[i].activityStart = max(range.lowerBound, days[i].date)
                days[i].activityEnd = min(range.upperBound, end)
            }
            if sessionsAvailable { days[i].prompts = 0; days[i].parallelSeconds = 0; days[i].sessionSeconds = 0 }
        }
        let input = inputs.filter { $0.at <= now }.sorted { $0.at < $1.at }
        for (a,b) in zip(input, input.dropFirst()) where a.isCodex && b.isCodex {
            let gap = b.at.timeIntervalSince(a.at)
            if gap > 0 && gap <= 120 { distribute(a.at, b.at) { i, seconds in days[i].codexSeconds = (days[i].codexSeconds ?? 0) + seconds } }
        }
        func hour(_ d: Date) -> Date { calendar.dateInterval(of: .hour, for: d)!.start }
        var observedHours = Set<Date>()
        var tasks: [Date: Set<String>] = [:], switches: [Date: Int] = [:]
        var previous: PromptingSelection?
        for selection in selections.filter({ $0.at <= now }).sorted(by: { $0.at < $1.at }) {
            tasks[hour(selection.at), default: []].insert(selection.task)
            // Do not infer a switch across a long unobserved interval.
            if let previous, selection.at > previous.at, selection.at.timeIntervalSince(previous.at) <= 600, hour(previous.at) == hour(selection.at) {
                observedHours.insert(hour(selection.at))
                if previous.task != selection.task { switches[hour(selection.at), default: 0] += 1 }
            }
            previous = selection
        }
        func median(_ values: [Double]) -> Double? {
            let sorted = values.sorted(); guard !sorted.isEmpty else { return nil }
            return (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
        }
        for i in days.indices {
            // A lone click or a long capture gap cannot establish zero switching.
            let hours = observedHours.filter { dayIndex($0) == i }
            days[i].eligibleHours = hours.count
            days[i].switchesPerHour = median(hours.map { Double(switches[$0, default: 0]) })
            days[i].tasksPerHour = median(hours.map { Double(tasks[$0, default: []].count) })
        }
        var counts: [Int: [String: Int]] = [:]
        for message in messages where message.at <= now {
            if let i = dayIndex(message.at) { counts[i, default: [:]][message.task, default: 0] += 1 }
        }
        for (i, tasks) in counts {
            let total = tasks.values.reduce(0, +)
            days[i].prompts = total
            days[i].topTaskShare = Double(tasks.values.max()!) / Double(total)
        }
        // Merge overlaps within each task before counting parallel tasks.
        var edges: [(Date, Int)] = []
        for (_, intervals) in Dictionary(grouping: runs, by: \.task) {
            var merged: (Date, Date)?
            for run in intervals.filter({ $0.end > $0.start }).sorted(by: { $0.start < $1.start }) {
                if let current = merged, run.start <= current.1 { merged = (current.0, max(current.1, run.end)) }
                else {
                    if let current = merged { edges += [(current.0, 1), (current.1, -1)] }
                    merged = (run.start, run.end)
                }
            }
            if let current = merged { edges += [(current.0, 1), (current.1, -1)] }
        }
        var active = 0, previousEdge: Date?
        for (date, delta) in edges.sorted(by: { $0.0 < $1.0 }) {
            if let previousEdge, active >= 1 { distribute(previousEdge, date) { i, seconds in days[i].sessionSeconds = (days[i].sessionSeconds ?? 0) + seconds } }
            if let previousEdge, active >= 2 { distribute(previousEdge, date) { i, seconds in days[i].parallelSeconds = (days[i].parallelSeconds ?? 0) + seconds } }
            active += delta; previousEdge = date
        }
        return days
    }
}
