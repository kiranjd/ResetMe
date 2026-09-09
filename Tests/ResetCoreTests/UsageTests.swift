import XCTest
import CoreGraphics
@testable import ResetCore
final class UsageTests: XCTestCase {
    func testNotchContourFrameUsesActualExclusionAndDisplayOrigin() throws {
        let shape = try XCTUnwrap(NotchGeometry(screenFrame: CGRect(x: 1728, y: 0, width: 1512, height: 982), safeTop: 32,
            leftArea: CGRect(x: 1728, y: 950, width: 656, height: 32), rightArea: CGRect(x: 2584, y: 950, width: 656, height: 32)))
        XCTAssertEqual(shape.cutoutWidth, 200)
        XCTAssertEqual(shape.frame, CGRect(x: 2377, y: 943, width: 214, height: 39))
    }
    func testNoNotchDoesNotInventCameraGeometry() {
        XCTAssertNil(NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeTop: 0, leftArea: nil, rightArea: nil))
    }
    func testCreditExpiryUsesEarliestAvailableCredit() throws {
        let credits = try JSONDecoder().decode(ResetCredits.self, from: Data(#"{"availableCount":2,"credits":[{"expiresAt":10,"status":"used"},{"expiresAt":300,"status":"available"},{"expiresAt":200,"status":"available"}]}"#.utf8))
        XCTAssertEqual(credits.nextExpiry, Date(timeIntervalSince1970: 200))
    }
    func testPreferDistinctLimitMapAndDecodeSparseWindows() throws {
        let data = Data(#"{"rateLimits":{"limitId":"legacy","primary":{"usedPercent":5}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":99,"windowDurationMins":10080,"resetsAt":2000000000}},"spark":{"limitId":"spark","limitName":"Spark","primary":{"usedPercent":0,"windowDurationMins":300}}},"rateLimitResetCredits":{"availableCount":1}}"#.utf8)
        let value = try JSONDecoder().decode(UsageResponse.self, from: data)
        XCTAssertEqual(value.buckets.map(\.id), ["codex", "spark"])
        XCTAssertEqual(value.buckets[0].constraining?.remaining, 1)
        XCTAssertEqual(value.buckets[0].constraining?.name, "Weekly")
        XCTAssertEqual(value.buckets[1].constraining?.remaining, 100)
        XCTAssertEqual(value.rateLimitResetCredits?.availableCount, 1)
    }
    func testUnknownIsNotZeroAndClampsProviderOverflow() throws {
        let unknown = try JSONDecoder().decode(UsageResponse.self, from: Data(#"{"rateLimits":{"limitId":"codex"}}"#.utf8))
        XCTAssertNil(unknown.buckets.first?.constraining)
        XCTAssertEqual(LimitWindow(usedPercent: 110, windowDurationMins: nil, resetsAt: nil).remaining, 0)
        XCTAssertEqual(LimitWindow(usedPercent: -5, windowDurationMins: nil, resetsAt: nil).remaining, 100)
    }
    func testPaceRequiresTimeAndNeverCrossesResetOrReplenishment() {
        let base = Date(timeIntervalSince1970: 1000)
        func sample(_ seconds: Double, _ used: Double, _ reset: Double = 9000) -> UsageSample {
            UsageSample(timestamp: base.addingTimeInterval(seconds), used: used, resetAt: reset, bucketID: "codex")
        }
        XCTAssertNil(UsageMath.pointsPerHour(samples: [sample(0, 10), sample(60, 20)], bucketID: "codex", resetAt: 9000))
        XCTAssertEqual(UsageMath.pointsPerHour(samples: [sample(0, 10), sample(600, 12)], bucketID: "codex", resetAt: 9000), 12)
        XCTAssertNil(UsageMath.pointsPerHour(samples: [sample(0, 10), sample(600, 12, 10000)], bucketID: "codex", resetAt: 9000))
        XCTAssertNil(UsageMath.pointsPerHour(samples: [sample(0, 10), sample(300, 5), sample(600, 12)], bucketID: "codex", resetAt: 9000))
    }
    func testWeeklyResetSamplesStaySeparateFromConstrainingPace() {
        let timestamp = Date(timeIntervalSince1970: 100)
        let bucket = LimitBucket(
            limitId: "claude", limitName: "Claude",
            primary: LimitWindow(usedPercent: 80, windowDurationMins: 300, resetsAt: 500),
            secondary: LimitWindow(usedPercent: 20, windowDurationMins: 10_080, resetsAt: 900),
            planType: nil)
        let samples = UsageSampling.samples(from: [bucket], timestamp: timestamp)
        XCTAssertEqual(samples.map(\.bucketID), ["claude", "claude:weekly"])
        XCTAssertEqual(samples[0].used, 80)
        XCTAssertEqual(samples[0].resetAt, 500)
        XCTAssertEqual(samples[1].used, 20)
        XCTAssertEqual(samples[1].resetAt, 900)
    }
    func testComparisonRejectsInvalidInput() {
        XCTAssertEqual(UsageMath.comparison(amount: 48, unitPrice: 12), 4)
        XCTAssertNil(UsageMath.comparison(amount: 48, unitPrice: 0))
        XCTAssertNil(UsageMath.comparison(amount: -.infinity, unitPrice: 12))
    }
    func testClaudeUsageMapsSessionWeeklyAndScopedLimits() throws {
        let data = Data(#"{"five_hour":{"utilization":12.5,"resets_at":"2026-09-09T12:00:00Z"},"seven_day":{"utilization":48,"resets_at":"2026-09-14T12:00:00.000Z"},"seven_day_sonnet":{"utilization":31},"limits":[{"kind":"weekly_scoped","group":"weekly","percent":22,"resets_at":"2026-09-15T12:00:00Z","scope":{"model":{"id":"claude-fable","display_name":"Fable"}}}]}"#.utf8)
        let snapshot = try JSONDecoder().decode(ClaudeUsagePayload.self, from: data).snapshot()
        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(snapshot.buckets.map(\.id), ["claude", "claude-sonnet", "claude-weekly-scoped-claude-fable"])
        XCTAssertEqual(snapshot.buckets[0].primary?.usedPercent, 12.5)
        XCTAssertEqual(snapshot.buckets[0].primary?.windowDurationMins, 300)
        XCTAssertEqual(snapshot.buckets[0].secondary?.usedPercent, 48)
        XCTAssertEqual(snapshot.buckets[2].name, "Fable only")
    }
    func testClaudeUsageRejectsEmptyAndIgnoresMalformedWindows() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(ClaudeUsagePayload.self, from: Data("{}".utf8)).snapshot()) {
            XCTAssertEqual($0 as? ClaudeUsagePayloadError, .noUsableLimits)
        }
        let partial = try JSONDecoder().decode(
            ClaudeUsagePayload.self,
            from: Data(#"{"five_hour":{"resets_at":"bad"},"seven_day":{"utilization":7}}"#.utf8)).snapshot()
        XCTAssertEqual(partial.buckets.count, 1)
        XCTAssertEqual(partial.buckets[0].primary?.usedPercent, 7)
        XCTAssertNil(partial.buckets[0].primary?.resetsAt)
        let unknownScoped = try JSONDecoder().decode(
            ClaudeUsagePayload.self,
            from: Data(#"{"seven_day":{"utilization":7},"limits":[{"kind":"daily_scoped","group":"daily","percent":99,"scope":{"model":{"display_name":"Mystery"}}}]}"#.utf8)).snapshot()
        XCTAssertEqual(unknownScoped.buckets.map(\.id), ["claude"])
    }
    func testClaudeHTTPStatusNeverTurnsFailureIntoAllowance() throws {
        let usable = Data(#"{"five_hour":{"utilization":12}}"#.utf8)
        XCTAssertEqual(try ClaudeUsageHTTPDecoder.snapshot(statusCode: 200, data: usable).buckets.count, 1)
        for (status, expected) in [(401, ClaudeUsageHTTPError.unauthorized), (403, .forbidden),
                                   (429, .rateLimited), (503, .serverUnavailable), (418, .invalidResponse)] {
            XCTAssertThrowsError(try ClaudeUsageHTTPDecoder.snapshot(statusCode: status, data: usable)) {
                XCTAssertEqual($0 as? ClaudeUsageHTTPError, expected)
            }
        }
        XCTAssertThrowsError(try ClaudeUsageHTTPDecoder.snapshot(statusCode: 200, data: Data("null".utf8))) {
            XCTAssertEqual($0 as? ClaudeUsageHTTPError, .invalidResponse)
        }
    }
    func testClaudeCredentialRequiresTokenAndFutureExpiry() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let valid = try JSONDecoder().decode(
            ClaudeCredentialPayload.self,
            from: Data(#"{"claudeAiOauth":{"accessToken":" private-token ","expiresAt":3000000}}"#.utf8))
        XCTAssertEqual(try valid.validatedAccessToken(now: now), "private-token")
        let expired = try JSONDecoder().decode(
            ClaudeCredentialPayload.self,
            from: Data(#"{"claudeAiOauth":{"accessToken":"token","expiresAt":1000000}}"#.utf8))
        XCTAssertThrowsError(try expired.validatedAccessToken(now: now)) {
            XCTAssertEqual($0 as? ClaudeCredentialPayloadError, .expired)
        }
        let malformed = try JSONDecoder().decode(ClaudeCredentialPayload.self, from: Data("{}".utf8))
        XCTAssertThrowsError(try malformed.validatedAccessToken(now: now)) {
            XCTAssertEqual($0 as? ClaudeCredentialPayloadError, .malformed)
        }
    }
}
