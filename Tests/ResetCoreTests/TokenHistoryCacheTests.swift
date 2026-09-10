import XCTest
@testable import ResetCore

final class TokenHistoryCacheTests: XCTestCase {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    func testRelaunchCachePreservesAggregatedStats() throws {
        let today = calendar.startOfDay(for: Date())
        var day = TokenDay(date: today, tokens: 1234)
        day.input = 1000; day.output = 234; day.inputCost = 2; day.pricedTokens = 1234
        let saved = TokenHistoryCache(provider: .codex, roots: ["/profile/sessions"], days: [day])
        let decoded = try JSONDecoder().decode(TokenHistoryCache.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded.provider, .codex)
        XCTAssertEqual(decoded.roots, ["/profile/sessions"])
        XCTAssertEqual(decoded.displayDays(now: today, calendar: calendar).last?.tokens, 1234)
        XCTAssertEqual(decoded.displayDays(now: today, calendar: calendar).last?.cost, 2)
    }
    func testMidnightKeepsYesterdayAndLeavesNewDayUnknown() {
        let yesterday = calendar.startOfDay(for: Date())
        let today = calendar.date(byAdding: .day, value: 1, to: yesterday)!
        let cache = TokenHistoryCache(provider: .codex, roots: [], days: [TokenDay(date: yesterday, tokens: 42)])
        let days = cache.displayDays(now: today, calendar: calendar)
        XCTAssertEqual(days.count, 14)
        XCTAssertEqual(days[12].date, yesterday)
        XCTAssertEqual(days[12].tokens, 42)
        XCTAssertEqual(days[13].date, today)
        XCTAssertNil(days[13].tokens)
    }
    func testOldCacheDoesNotFabricateCurrentStats() {
        let today = calendar.startOfDay(for: Date())
        let cache = TokenHistoryCache(provider: .claude, roots: [], days: [TokenDay(date: today.addingTimeInterval(-30 * 86400), tokens: 999)])
        XCTAssertTrue(cache.displayDays(now: today, calendar: calendar).allSatisfy { $0.tokens == nil })
    }
}
