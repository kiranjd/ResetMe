import XCTest
import SQLite3
@testable import ResetCore

final class PromptingHistoryTests: XCTestCase {
    func testPrivateMessageFilteringWithoutComputerHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let task = "00000000-0000-0000-0000-000000000001"
        let file = root.appendingPathComponent("rollout-" + task + ".jsonl")
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(3600)
        let stamp = ISO8601DateFormatter()
        func line(_ at: Date, _ payload: [String: Any]) throws -> String {
            String(data: try JSONSerialization.data(withJSONObject: ["timestamp": stamp.string(from: at), "type": "event_msg", "payload": payload]), encoding: .utf8)! + "\n"
        }
        func message(_ id: String, _ text: String) -> [String: Any] {
            ["type": "item_completed", "thread_id": task, "item": ["type": "UserMessage", "id": id, "content": [["type": "text", "text": text]]]]
        }
        let prompt = try line(start, message("1", "Synthetic fixture"))
        var contents = prompt + prompt
        contents += try line(start, message("2", "<environment_context>\nsetup\n</environment_context>"))
        contents += try line(start, message("3", "Automation: fixture"))
        contents += try line(start, message("heartbeat", "<heartbeat>Scheduled fixture</heartbeat>"))
        contents += try line(start.addingTimeInterval(-100), message("4", "Inherited fixture"))
        contents += try line(start, ["type": "task_started", "turn_id": "t", "thread_id": task])
        contents += try line(start.addingTimeInterval(60), ["type": "task_complete", "turn_id": "t", "thread_id": task])
        let response: [String: Any] = ["timestamp": stamp.string(from: start), "type": "response_item", "payload": ["type": "message", "role": "user", "content": [["type": "input_text", "text": "Synthetic fixture"]]]]
        contents += String(data: try JSONSerialization.data(withJSONObject: response), encoding: .utf8)! + "\n"
        try contents.write(to: file, atomically: true, encoding: .utf8)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("state_5.sqlite").path, &db), SQLITE_OK)
        let sql = "CREATE TABLE threads(id TEXT, rollout_path TEXT, name TEXT, created_at INTEGER, updated_at INTEGER, thread_source TEXT, source TEXT, title TEXT, cwd TEXT); INSERT INTO threads VALUES ('\(task)', '\(file.path)', 'Fixture', \(Int(start.timeIntervalSince1970)), \(Int(start.timeIntervalSince1970)), 'user', 'cli', 'Fixture', '/fixtures/project');"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        let agentTask = "00000000-0000-0000-0000-000000000002"
        let agentFile = root.appendingPathComponent("rollout-" + agentTask + ".jsonl")
        try contents.replacingOccurrences(of: task, with: agentTask).write(to: agentFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(sqlite3_exec(db, "INSERT INTO threads VALUES ('\(agentTask)', '\(agentFile.path)', 'Agent task', \(Int(start.timeIntervalSince1970)), \(Int(start.timeIntervalSince1970)), 'agent_created_thread', 'cli', 'Agent task', '/fixtures/project');", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let segment = root.appendingPathComponent("activity/segment")
        try FileManager.default.createDirectory(at: segment, withIntermediateDirectories: true)
        let events = try (0..<10).map { i -> String in
            let row: [String: Any] = ["id": i, "timestamp": stamp.string(from: start.addingTimeInterval(Double(i * 60))), "kind": "mouse.click", "app": ["bundleIdentifier": "com.openai.codex"], "mouse": ["target": ["role": "AXButton", "title": "Fixture"]]]
            return String(data: try JSONSerialization.data(withJSONObject: row), encoding: .utf8)!
        }.joined(separator: "\n")
        try events.write(to: segment.appendingPathComponent("events.jsonl"), atomically: true, encoding: .utf8)
        let reader = PromptingHistory()
        let result = await reader.read(now: start.addingTimeInterval(1000), codexRoot: root, activityRoot: root.appendingPathComponent("activity"), screenTimeRoot: root.appendingPathComponent("no-screen-time"))
        XCTAssertTrue(result.sessionsAvailable)
        XCTAssertEqual(result.contextTasks.map(\.id), [task])
        XCTAssertEqual(result.contextMessages.count, 1)
        let day = try XCTUnwrap(result.days.last)
        XCTAssertEqual(day.prompts, 1)
        XCTAssertNil(day.codexSeconds) // Never substitute input gaps for Screen Time.
        XCTAssertNil(day.switchesPerHour)
        XCTAssertNil(day.tasksPerHour)
        XCTAssertEqual(day.parallelSeconds, 0)
        let cached = await reader.read(now: start.addingTimeInterval(1001), codexRoot: root, activityRoot: root.appendingPathComponent("activity"), screenTimeRoot: root.appendingPathComponent("no-screen-time"))
        XCTAssertEqual(cached.days.last?.prompts, 1)
    }
}
