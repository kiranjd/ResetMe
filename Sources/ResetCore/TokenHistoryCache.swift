import Foundation

/// Only aggregated counters are cached, scoped to their provider and source roots.
public struct TokenHistoryCache: Codable, Sendable {
    public var provider: UsageProvider
    public var roots: [String]
    public var days: [TokenDay]
    public init(provider: UsageProvider, roots: [String], days: [TokenDay]) {
        self.provider = provider; self.roots = roots; self.days = days
    }
    public func displayDays(now: Date = Date(), calendar: Calendar = .current, dayCount: Int = 14) -> [TokenDay] {
        let start = calendar.date(byAdding: .day, value: -(max(1, dayCount) - 1), to: calendar.startOfDay(for: now))!
        return (0..<max(1, dayCount)).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            // A timezone change requires a fresh scan; don't move a previous day's
            // totals into today's column or turn a new unknown day into zero.
            return days.first { $0.date == date } ?? TokenDay(date: date, tokens: nil)
        }
    }
}
