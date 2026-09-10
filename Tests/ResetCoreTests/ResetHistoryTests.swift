import XCTest
@testable import ResetCore

final class ResetHistoryTests: XCTestCase {
    let origin = Date(timeIntervalSince1970: 1_800_000_000)
    let week: Double = 604_800
    func observation(_ time: Double, used: Double, end: Double?, duration: Int = 10_080,
                     provider: UsageProvider = .codex, source: QuotaObservation.Source = .live,
                     plan: String? = nil) -> QuotaObservation {
        QuotaObservation(provider: provider, bucketID: provider.rawValue, bucketName: provider.displayName,
            durationMinutes: duration, used: used, resetsAt: end.map { origin.timeIntervalSince1970 + $0 },
            timestamp: origin.addingTimeInterval(time), source: source, plan: plan)
    }
    func testInitialReadDoesNotInventResets() {
        XCTAssertTrue(ResetHistory.recovered(from: [observation(100, used: 20, end: week)]).isEmpty)
    }
    func testScheduledBoundaryUsesProviderTimeNotDetectionTimeOrPercentDrop() {
        let events = ResetHistory.recovered(from: [observation(0, used: 5, end: 100), observation(500, used: 10, end: week + 100)])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .scheduled)
        XCTAssertEqual(events.first?.date, origin.addingTimeInterval(100))
        XCTAssertEqual(events.first?.estimated, false)
    }
    func testEarlyResetUsesInferredCycleStartEvenWhenObservationWasDelayedTwoDays() {
        let events = ResetHistory.recovered(from: [observation(0, used: 100, end: week), observation(172_800, used: 38, end: week + 300)])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.date, origin.addingTimeInterval(300))
        XCTAssertEqual(events.first?.kind, .cycleRestart)
        XCTAssertEqual(events.first?.estimated, true)
        XCTAssertEqual(events.first?.detectedAt, origin.addingTimeInterval(172_800))
    }
    func testKeepsEveryEarlyResetIncludingSeveralInSameDay() {
        let values = [observation(0, used: 90, end: week),
                      observation(100, used: 0, end: week + 100),
                      observation(120, used: 70, end: week + 100),
                      observation(160, used: 0, end: week + 160)]
        let events = ResetHistory.recovered(from: values)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.date), [origin.addingTimeInterval(100), origin.addingTimeInterval(160)])
    }
    func testMovingDeadlineWithoutRestorationIsNotEnoughEvidenceOfAnEarlyReset() {
        let events = ResetHistory.recovered(from: [observation(0, used: 5, end: week), observation(200, used: 10, end: week + 100)])
        XCTAssertTrue(events.isEmpty)
    }
    func testLiveRestorationWithoutDeadlineChangeIsNotCalledManualReset() {
        let events = ResetHistory.recovered(from: [observation(0, used: 80, end: week), observation(60, used: 10, end: week)])
        XCTAssertEqual(events.first?.kind, .allowanceRestored)
        XCTAssertEqual(events.first?.estimated, true)
        XCTAssertEqual(events.first?.previousObservation, origin)
    }
    func testCachedPercentageChangesAndBackwardsCyclesDoNotCreatePhantomResets() {
        let values = [observation(0, used: 90, end: week, source: .codexHistory),
                      observation(60, used: 80, end: week + 1, source: .codexHistory),
                      observation(100, used: 10, end: week + 100, source: .codexHistory),
                      observation(200, used: 90, end: week, source: .codexHistory),
                      observation(220, used: 10, end: week + 101, source: .codexHistory)]
        XCTAssertEqual(ResetHistory.recovered(from: values).count, 1)
    }
    func testOfflineGapDoesNotManufactureUnobservedRecurringResets() {
        let events = ResetHistory.recovered(from: [observation(0, used: 50, end: 100),
            observation(3 * week, used: 70, end: 4 * week)])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.date, origin.addingTimeInterval(100))
    }
    func testExpiredCachedResponseDoesNotEraseScheduledBoundaryEvidence() {
        let values = [observation(0, used: 80, end: 100),
                      observation(200, used: 80, end: 100),
                      observation(500, used: 20, end: week + 100)]
        let events = ResetHistory.recovered(from: values)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .scheduled)
        XCTAssertEqual(events.first?.date, origin.addingTimeInterval(100))
    }
    func testUnusedFloatingDeadlinesNeverBecomeResets() {
        let values = (0..<100).map { index in
            observation(Double(index) * 60, used: 0, end: week + Double(index) * 60, source: .codexHistory)
        }
        XCTAssertTrue(ResetHistory.recovered(from: values).isEmpty)
    }
    func testPlanChangeStartsNewBaseline() {
        XCTAssertTrue(ResetHistory.recovered(from: [observation(0, used: 90, end: week, plan: "plus"),
            observation(100, used: 0, end: week + 100, plan: "pro")]).isEmpty)
    }
    func testProviderAndWindowHistoriesAreIndependent() {
        var history = ResetHistory()
        history.observe([observation(0, used: 80, end: 100), observation(60, used: 0, end: week, provider: .claude),
                         observation(200, used: 20, end: week + 100)])
        XCTAssertEqual(history.events.count, 1)
        XCTAssertEqual(history.events.first?.provider, .codex)
    }
    func testPersistenceRetainsEventsAndBaselineAcrossRestarts() throws {
        var history = ResetHistory()
        history.observe([observation(0, used: 90, end: week), observation(100, used: 0, end: week + 100)])
        let data = try JSONEncoder().encode(history)
        var restarted = try JSONDecoder().decode(ResetHistory.self, from: data)
        restarted.observe([observation(200_000, used: 80, end: week + 100), observation(200_100, used: 0, end: week + 200_100)])
        XCTAssertEqual(restarted.events.count, 2)
        XCTAssertEqual(restarted.events.first?.date, origin.addingTimeInterval(100))
    }
    func testRepeatedBackfillAndLiveObservationMergeSameReset() {
        let first = ResetHistory.recovered(from: [observation(0, used: 90, end: week), observation(200, used: 0, end: week + 100)])
        let backfill = ResetHistory.recovered(from: [observation(0, used: 90, end: week, source: .codexHistory), observation(101, used: 0, end: week + 101, source: .codexHistory)])
        var history = ResetHistory(); history.merge(first); history.merge(backfill); history.merge(backfill)
        XCTAssertEqual(history.events.count, 1)
        XCTAssertEqual(history.events.first?.detectedAt, origin.addingTimeInterval(101))
    }
    func testBackfillCanResolveAnUnknownRestorationWithoutCountingItTwice() {
        let observed = ResetHistory.recovered(from: [observation(0, used: 90, end: nil), observation(200, used: 10, end: week + 100)])
        let recovered = ResetHistory.recovered(from: [observation(0, used: 90, end: week, source: .codexHistory), observation(150, used: 10, end: week + 100, source: .codexHistory)])
        var history = ResetHistory(); history.merge(observed); history.merge(recovered)
        XCTAssertEqual(history.events.count, 1)
        XCTAssertEqual(history.events.first?.kind, .cycleRestart)
        XCTAssertEqual(history.events.first?.date, origin.addingTimeInterval(100))
    }
    func testLaterRestorationWithinTheSameCycleRemainsASeparateEvent() {
        let values = [observation(0, used: 90, end: week), observation(100, used: 0, end: week + 100),
                      observation(200, used: 70, end: week + 100), observation(300, used: 0, end: week + 100)]
        XCTAssertEqual(ResetHistory.recovered(from: values).count, 2)
    }
    func testOnlyWeeklySnapshotWindowIsCapturedEvenWhenFiveHourIsPresent() {
        let bucket = LimitBucket(limitId: "codex", limitName: "Codex", primary: LimitWindow(usedPercent: 20, windowDurationMins: 300, resetsAt: nil), secondary: LimitWindow(usedPercent: 90, windowDurationMins: 10_080, resetsAt: nil), planType: nil)
        let values = QuotaObservation.snapshot(ProviderUsageSnapshot(provider: .codex, buckets: [bucket]), at: origin)
        XCTAssertEqual(values.map(\.durationMinutes), [10_080])
    }
    func testFiveHourResetsAreExcludedFromHistory() {
        let values = [observation(0, used: 80, end: 100, duration: 300),
                      observation(200, used: 0, end: 18_100, duration: 300)]
        XCTAssertTrue(ResetHistory.recovered(from: values).isEmpty)
        let limits: [String: Any] = ["primary": ["used_percent": 20.0, "window_minutes": 300, "resets_at": 1_800_018_000.0]]
        XCTAssertTrue(QuotaObservation.codexRecord(limits, at: origin).isEmpty)
    }
    func testGroupingKeepsAllEventsOnFirstVisibleDayAndSeparatesProviders() {
        let events = ResetHistory.recovered(from: [observation(0, used: 90, end: week), observation(100, used: 0, end: week + 100), observation(200, used: 70, end: week + 100), observation(300, used: 0, end: week + 300)])
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.startOfDay(for: origin)
        let groups = ResetDay.groups(events, provider: .codex, start: day, end: day.addingTimeInterval(86400), calendar: calendar)
        XCTAssertEqual(groups.count, 1); XCTAssertEqual(groups.first?.events.count, 2)
        XCTAssertTrue(ResetDay.groups(events, provider: .claude, start: day, end: day.addingTimeInterval(86400), calendar: calendar).isEmpty)
    }
    func testQuotaBackfillDoesNotRequireTokenCountersOrReadConversationContent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let date = ISO8601DateFormatter().string(from: origin)
        let line = "{\"timestamp\":\"\(date)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":null,\"rate_limits\":{\"limit_id\":\"codex\",\"primary\":{\"used_percent\":5,\"window_minutes\":10080,\"resets_at\":1800604800}}}}\n"
        let file = root.appendingPathComponent("session-00000000-0000-0000-0000-000000000001.jsonl")
        try line.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: origin], ofItemAtPath: file.path)
        let result = TokenHistory.read(root: root, now: origin, dayCount: 14)
        XCTAssertEqual(result.quotaObservations.count, 1)
        XCTAssertEqual(result.quotaObservations.first?.durationMinutes, 10_080)
        XCTAssertTrue(result.days.allSatisfy { $0.tokens == nil })
    }
}
