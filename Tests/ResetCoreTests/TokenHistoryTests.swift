import XCTest
@testable import ResetCore
final class TokenHistoryTests: XCTestCase {
    func testProviderHistoryRootsRespectProfileBoundaries() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let cwd = URL(fileURLWithPath: "/work/reset", isDirectory: true)
        XCTAssertEqual(
            TokenHistory.defaultRoot(home: home, environment: [:], workingDirectory: cwd).path,
            "/Users/test/.codex/sessions")
        XCTAssertEqual(
            TokenHistory.defaultRoot(home: home, environment: ["CODEX_HOME": ""], workingDirectory: cwd).path,
            "/Users/test/.codex/sessions")
        XCTAssertEqual(
            TokenHistory.defaultRoot(home: home, environment: ["CODEX_HOME": "/profiles/codex"], workingDirectory: cwd).path,
            "/profiles/codex/sessions")
        XCTAssertEqual(
            TokenHistory.defaultRoot(home: home, environment: ["CODEX_HOME": "profiles/codex"], workingDirectory: cwd).path,
            "/work/reset/profiles/codex/sessions")

        XCTAssertEqual(
            ClaudeTokenHistory.defaultRoots(home: home, environment: ["CLAUDE_CONFIG_DIR": "/profiles/claude"])
                .map(\.path),
            ["/profiles/claude/projects"])
        XCTAssertEqual(
            ClaudeTokenHistory.defaultRoots(home: home, environment: [:]).map(\.path),
            [
                "/Users/test/.config/claude/projects",
                "/Users/test/.claude/projects",
                "/Users/test/Library/Application Support/Claude/local-agent-mode-sessions",
            ])
    }

    func testCumulativeCountersCountDeltasAndLeaveMissingDaysUnknown() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-60))
        func event(_ total: Int, _ last: Int) -> String {
            "{\"type\":\"event_msg\",\"timestamp\":\"\(stamp)\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(total)},\"last_token_usage\":{\"total_tokens\":\(last)}}}}"
        }
        let oversized = "{\"type\":\"response_item\",\"content\":\"" + String(repeating: "x", count: 600_000) + "\"}"
        let content = [event(1000,100),oversized,event(1000,100),event(1300,300),event(50,50)].joined(separator: "\n")
        try content.write(to: root.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
        let days = TokenHistory.days(root: root, now: now)
        XCTAssertEqual(days.count, 7)
        let extended = TokenHistory.days(root: root, now: now, dayCount: 14)
        XCTAssertEqual(extended.count, 14)
        XCTAssertEqual(extended.last?.tokens, days.last?.tokens)
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: extended[0].date, to: extended[13].date).day, 13)
        XCTAssertEqual(days.compactMap(\.tokens).reduce(0,+),450)
        XCTAssertTrue(days.dropLast().allSatisfy { $0.tokens == nil })
    }
    func testCostSplitsCacheAndOutputAndDoesNotGuessUnknownModel() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(), stamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-10))
        func context(_ model: String) -> [String: Any] { ["type": "turn_context", "payload": ["model": model]] }
        func event(_ input: Int, _ cached: Int, _ output: Int, _ lastInput: Int, _ lastCached: Int, _ lastOutput: Int) -> [String: Any] {
            ["type": "event_msg", "timestamp": stamp, "payload": ["type": "token_count", "info": [
                "total_token_usage": ["input_tokens": input, "cached_input_tokens": cached, "output_tokens": output, "total_tokens": input + output],
                "last_token_usage": ["input_tokens": lastInput, "cached_input_tokens": lastCached, "output_tokens": lastOutput, "total_tokens": lastInput + lastOutput]
            ]]]
        }
        let first = event(1000,800,100,1000,800,100)
        let records: [[String: Any]] = [context("gpt-6-astra"), first, first,
            context("unknown-model"), event(2000,1600,200,1000,800,100),
            context("gpt-5.6-sol"), event(302000,101600,1200,300000,100000,1000)]
        let lines = try records.map { String(data: try JSONSerialization.data(withJSONObject: $0), encoding: .utf8)! }.joined(separator: "\n")
        try lines.write(to: root.appendingPathComponent("cost.jsonl"), atomically: true, encoding: .utf8)
        let day = try XCTUnwrap(TokenHistory.days(root: root, now: now).last)
        XCTAssertEqual(day.input,302000); XCTAssertEqual(day.cached,101600); XCTAssertEqual(day.output,1200)
        XCTAssertEqual(day.topModel,"gpt-5.6-sol")
        XCTAssertEqual(day.modelTokens["gpt-6-astra"],1100)
        XCTAssertEqual(day.unpriced,1100)
        XCTAssertEqual(day.inputCost,1.602,accuracy:0.000001)
        XCTAssertEqual(day.cachedCost,0.0408,accuracy:0.000001)
        XCTAssertEqual(day.outputCost,0.035,accuracy:0.000001)
    }

    func testClaudeHistoryUsesAssistantUsageAndDeduplicatesStreamingRows() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(), stamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-10))
        func row(input: Int, cacheCreate: Int, cacheRead: Int, output: Int) throws -> String {
            let value: [String: Any] = [
                "type": "assistant", "timestamp": stamp, "sessionId": "session", "requestId": "request",
                "message": ["id": "message", "model": "claude-sonnet-4-6", "usage": [
                    "input_tokens": input, "cache_creation_input_tokens": cacheCreate,
                    "cache_read_input_tokens": cacheRead, "output_tokens": output,
                ]],
            ]
            return String(data: try JSONSerialization.data(withJSONObject: value), encoding: .utf8)!
        }
        let ignored = #"{"type":"user","message":{"content":"private transcript is ignored"}}"#
        let content = try [ignored, row(input: 10, cacheCreate: 20, cacheRead: 30, output: 4),
                           row(input: 11, cacheCreate: 22, cacheRead: 33, output: 5)].joined(separator: "\n")
        try content.write(to: root.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
        let day = try XCTUnwrap(ClaudeTokenHistory.days(roots: [root], now: now).last)
        XCTAssertEqual(day.tokens, 71)
        XCTAssertEqual(day.input, 66)
        XCTAssertEqual(day.cached, 33)
        XCTAssertEqual(day.output, 5)
        XCTAssertEqual(day.unpriced, 71)
        XCTAssertNil(day.cost)
        XCTAssertEqual(day.topModel, "claude-sonnet-4-6")
    }

}
