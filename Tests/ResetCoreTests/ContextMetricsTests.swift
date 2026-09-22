import XCTest
@testable import ResetCore
final class ContextMetricsTests: XCTestCase {
    func testTasksInSameContextAndIdleHours() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = cal.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let tasks = [ContextTask(id: "a", title: "Web", context: "Speakmac"), .init(id: "b", title: "Mac", context: "Speakmac"), .init(id: "c", title: "Other", context: "ResetMe")]
        let messages: [PromptingMessage] = [.init(at: day, task: "a"), .init(at: day, task: "a"), .init(at: day, task: "b"), .init(at: day.addingTimeInterval(7200), task: "a"), .init(at: day.addingTimeInterval(7200), task: "c")]
        let hours = ContextMetrics.hours(messages: messages, tasks: tasks, day: day, calendar: cal)
        XCTAssertEqual(hours.count, 2)
        XCTAssertEqual(hours[0].tasks.count, 2)
        XCTAssertEqual(hours[0].contexts, ["Speakmac"])
        XCTAssertEqual(ContextMetrics.average(hours), 1.5)
    }
    func testUnknownContextExcludedUntilAssigned() {
        let day = Date()
        let tasks = [ContextTask(id: "a", title: "Unclear", context: nil)]
        let messages = [PromptingMessage(at: day, task: "a"), .init(at: day, task: "excluded-task")]
        let unknown = ContextMetrics.hours(messages: messages, tasks: tasks, day: day)
        XCTAssertNil(ContextMetrics.average(unknown))
        XCTAssertEqual(unknown[0].tasks.count, 1)
        let edited = ContextMetrics.hours(messages: messages, tasks: tasks, day: day, overrides: ["a": " Focus "])
        XCTAssertEqual(ContextMetrics.average(edited), 1)
        XCTAssertEqual(edited[0].contexts, ["Focus"])
        XCTAssertNil(ContextMetrics.average([]))
    }
    func testWorktreesGroupAndPersonalFoldersRemainUnknown() {
        XCTAssertEqual(ContextMetrics.suggestedContext(cwd: "/Users/fixture/.codex/worktrees/test/vibe-code", title: "Mac work"), "Speakmac")
        XCTAssertEqual(ContextMetrics.suggestedContext(cwd: "/Users/fixture/things/vibe-code", title: "Web work"), "Speakmac")
        XCTAssertEqual(ContextMetrics.suggestedContext(cwd: "/Users/fixture/Developer/my-app", title: "Fix tests"), "my-app")
        XCTAssertEqual(ContextMetrics.suggestedContext(cwd: "/Users/fixture/.codex/worktrees/abcd/my-app", title: "Fix tests"), "my-app")
        XCTAssertNil(ContextMetrics.suggestedContext(cwd: "/Users/fixture", title: "Question"))
        XCTAssertNil(ContextMetrics.suggestedContext(cwd: "/Users/fixture/Documents/Codex/2026-09-23/task-123", title: "Question"))
        XCTAssertNil(ContextMetrics.suggestedContext(cwd: "/Users/fixture/things/self", title: "Unclear"))
    }
}
