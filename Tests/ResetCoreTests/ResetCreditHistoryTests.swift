import XCTest
@testable import ResetCore

final class ResetCreditHistoryTests: XCTestCase {
    private func credits(_ json: String) throws -> ResetCredits {
        try JSONDecoder().decode(ResetCredits.self, from: Data(json.utf8))
    }
    func testGrantUsesProviderTimestampAndNeverCountsAsAReset() throws {
        let response = try credits(#"{"availableCount":1,"credits":[{"id":"one","resetType":"codexRateLimits","grantedAt":100,"expiresAt":9999,"status":"available"}]}"#)
        var history = ResetHistory()
        history.observeCredits(response, provider: .codex, at: Date(timeIntervalSince1970: 500))
        history.observeCredits(response, provider: .codex, at: Date(timeIntervalSince1970: 600))
        XCTAssertEqual(history.creditGrants.count, 1)
        XCTAssertEqual(history.creditGrants.first?.date, Date(timeIntervalSince1970: 100))
        XCTAssertTrue(history.events.isEmpty)
    }
    func testPersistedGrantsSurviveUsedExpiredOrMissingCredits() throws {
        let response = try credits(#"{"credits":[{"id":"one","grantedAt":100,"status":"used"},{"id":"two","grantedAt":200,"status":"expired"}]}"#)
        var history = ResetHistory()
        history.observeCredits(response, provider: .codex, at: Date(timeIntervalSince1970: 500))
        history = try JSONDecoder().decode(ResetHistory.self, from: JSONEncoder().encode(history))
        history.observeCredits(nil, provider: .codex, at: Date(timeIntervalSince1970: 600))
        history.observeCredits(try credits(#"{"availableCount":0,"credits":[]}"#), provider: .codex, at: Date(timeIntervalSince1970: 700))
        XCTAssertEqual(history.creditGrants.count, 2)
    }
    func testCountExpiryAndMissingIdentityCannotInventGrantDates() throws {
        let response = try credits(#"{"availableCount":5,"credits":[{"id":"expiryOnly","expiresAt":9999,"status":"available"},{"grantedAt":100},{"id":"future","grantedAt":900},{"id":"negative","grantedAt":-1},{"id":"other","grantedAt":100,"resetType":"otherLimit"}]}"#)
        var history = ResetHistory()
        history.observeCredits(response, provider: .codex, at: Date(timeIntervalSince1970: 500))
        XCTAssertTrue(history.creditGrants.isEmpty)
    }
    func testCreditGrantsAreProviderScoped() throws {
        var history = ResetHistory()
        history.observeCredits(try credits(#"{"credits":[{"id":"one","grantedAt":100}]}"#), provider: .claude, at: Date(timeIntervalSince1970: 500))
        XCTAssertTrue(history.creditGrants.isEmpty)
    }
    func testChartGroupsGrantsSeparatelyFromResetCountsInLocalTime() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 19_800)!
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 100))
        let end = start.addingTimeInterval(86_400)
        let grants = [ResetCreditGrant(id: "one", provider: .codex, date: Date(timeIntervalSince1970: 100)),
                      ResetCreditGrant(id: "two", provider: .codex, date: Date(timeIntervalSince1970: 200)),
                      ResetCreditGrant(id: "end", provider: .codex, date: end)]
        let event = QuotaResetEvent(id: "reset", provider: .codex, bucketID: "codex", bucketName: "Codex",
            durationMinutes: 10_080, kind: .scheduled, date: Date(timeIntervalSince1970: 300),
            detectedAt: Date(timeIntervalSince1970: 400), previousObservation: Date(timeIntervalSince1970: 200),
            nextResetAt: 9000, estimated: false)
        let grouped = ResetDay.groups([event], credits: grants, provider: .codex, start: start, end: end, calendar: calendar)
        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(grouped.first?.events.count, 1)
        XCTAssertEqual(grouped.first?.creditGrants.count, 2)
        XCTAssertTrue(ResetDay.groups([event], credits: grants, provider: .claude, start: start, end: end, calendar: calendar).isEmpty)
        let grantOnly = ResetDay.groups([], credits: grants, provider: .codex, start: start, end: end, calendar: calendar)
        XCTAssertEqual(grantOnly.count, 1)
        XCTAssertTrue(grantOnly[0].events.isEmpty)
    }
}
