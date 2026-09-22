import XCTest
@testable import ResetCore

final class PromptingMetricsTests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    let midnight = Date(timeIntervalSince1970: 1_700_006_400)
    func testInputDoesNotBridgeIdleOtherAppsOrMidnightIncorrectly() {
        let start = calendar.startOfDay(for: midnight)
        let t = start.addingTimeInterval(86400)
        let inputs = [PromptingInput(at: t.addingTimeInterval(-30), isCodex: true), .init(at: t.addingTimeInterval(30), isCodex: true), .init(at: t.addingTimeInterval(60), isCodex: false), .init(at: t.addingTimeInterval(90), isCodex: true), .init(at: t.addingTimeInterval(300), isCodex: true)]
        let result = PromptingMetrics.days(inputs: inputs, selections: [], messages: [], runs: [], activityRange: inputs.first!.at...inputs.last!.at, sessionsAvailable: false, now: t.addingTimeInterval(600), calendar: calendar, count: 2)
        XCTAssertEqual(result[0].codexSeconds, 30)
        XCTAssertEqual(result[1].codexSeconds, 30)
        XCTAssertNil(result[0].prompts)
        XCTAssertNil(result[1].switchesPerHour)
    }
    func testParallelCountsDistinctTasksAndClipsAtMidnight() {
        let t = calendar.startOfDay(for: midnight)
        let runs: [PromptingRun] = [.init(start: t.addingTimeInterval(-120), end: t.addingTimeInterval(120), task: "a"), .init(start: t.addingTimeInterval(-90), end: t.addingTimeInterval(90), task: "a"), .init(start: t.addingTimeInterval(-30), end: t.addingTimeInterval(60), task: "b")]
        let result = PromptingMetrics.days(inputs: [], selections: [], messages: [], runs: runs, activityRange: nil, sessionsAvailable: true, now: t.addingTimeInterval(300), calendar: calendar, count: 2)
        XCTAssertEqual(result[0].parallelSeconds, 30)
        XCTAssertEqual(result[1].parallelSeconds, 60)
        XCTAssertEqual(result[0].sessionSeconds, 120)
        XCTAssertEqual(result[1].sessionSeconds, 120)
        XCTAssertEqual(result[0].parallelShare, 0.25)
        XCTAssertEqual(result[1].parallelShare, 0.5)
        XCTAssertNil(PromptingDay(date: t).parallelShare)
        XCTAssertNil(result[1].codexSeconds)
    }
    func testParallelShareDistinguishesSingleTaskFromNoTiming() {
        let t = calendar.startOfDay(for: midnight)
        let single = PromptingMetrics.days(inputs: [], selections: [], messages: [], runs: [.init(start: t, end: t.addingTimeInterval(60), task: "a")], activityRange: nil, sessionsAvailable: true, now: t.addingTimeInterval(300), calendar: calendar, count: 1)[0]
        XCTAssertEqual(single.parallelShare, 0)
        let empty = PromptingMetrics.days(inputs: [], selections: [], messages: [], runs: [], activityRange: nil, sessionsAvailable: true, now: t.addingTimeInterval(300), calendar: calendar, count: 1)[0]
        XCTAssertNil(empty.parallelShare)
    }
    func testRatesUseObservedSelectionPairsWithoutInputMinuteThreshold() {
        let t = calendar.startOfDay(for: midnight)
        let input: [PromptingInput] = []
        let selections: [PromptingSelection] = [.init(at: t, task: "a"), .init(at: t.addingTimeInterval(60), task: "b"), .init(at: t.addingTimeInterval(90), task: "b"), .init(at: t.addingTimeInterval(120), task: "a")]
        let messages: [PromptingMessage] = [.init(at: t, task: "a"), .init(at: t, task: "a"), .init(at: t, task: "b")]
        let result = PromptingMetrics.days(inputs: input, selections: selections, messages: messages, runs: [], activityRange: t...t.addingTimeInterval(600), sessionsAvailable: true, now: t.addingTimeInterval(3600), calendar: calendar, count: 1)[0]
        XCTAssertEqual(result.switchesPerHour, 2)
        XCTAssertEqual(result.tasksPerHour, 2)
        XCTAssertEqual(result.eligibleHours, 1)
        XCTAssertEqual(result.prompts, 3)
        XCTAssertEqual(result.topTaskShare!, 2.0 / 3, accuracy: 0.0001)
        let missing = PromptingMetrics.days(inputs: input, selections: [], messages: [], runs: [], activityRange: t...t.addingTimeInterval(600), sessionsAvailable: true, now: t.addingTimeInterval(3600), calendar: calendar, count: 1)[0]
        XCTAssertNil(missing.switchesPerHour)
        XCTAssertNil(missing.topTaskShare)
    }
    func testIsolatedSelectionsDoNotInventZeroSwitching() {
        let t = calendar.startOfDay(for: midnight)
        let selections: [PromptingSelection] = [.init(at: t, task: "a"), .init(at: t.addingTimeInterval(1800), task: "b")]
        let result = PromptingMetrics.days(inputs: [], selections: selections, messages: [], runs: [], activityRange: nil, sessionsAvailable: false, now: t.addingTimeInterval(3600), calendar: calendar, count: 1)
        XCTAssertNil(result[0].switchesPerHour)
    }
    func testMissingSourcesRemainMissing() async {
        let reader = PromptingHistory()
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let result = await reader.read(codexRoot: empty, activityRoot: empty, screenTimeRoot: empty)
        XCTAssertFalse(result.sessionsAvailable)
        XCTAssertTrue(result.days.allSatisfy { $0.prompts == nil && $0.parallelSeconds == nil && $0.codexSeconds == nil })
    }
}
