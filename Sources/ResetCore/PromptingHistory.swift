import Foundation
import Darwin
import SQLite3
import CryptoKit

public struct PromptingSnapshot: Sendable {
    public var days: [PromptingDay]
    public var updatedAt: Date
    public var sessionsAvailable: Bool
    public var incompleteRuns: Int
    public var unreadableFiles: Int
    public var screenTimeAccessDenied: Bool = false
    public var contextTasks: [ContextTask] = []
    public var contextMessages: [PromptingMessage] = []
}

/// Optional read-only adapters. No capture, permission requests, network, or persisted content.
/// Only timestamps, task metadata and identifiers survive parsing; prompt text is never returned.
public actor PromptingHistory {
    public init() {}
    private struct SessionData {
        var messages: [String: PromptingMessage] = [:]
        var starts: [String: Date] = [:]
        var ends: [String: Date] = [:]
    }
    private struct Cache { var modified: Date; var size: Int; var data: SessionData }
    private var cache: [String: Cache] = [:]
    private let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private let plain = ISO8601DateFormatter()
    private func date(_ value: Any?) -> Date? {
        if let value = value as? Double { return Date(timeIntervalSince1970: value > 1e12 ? value / 1000 : value) }
        guard let value = value as? String else { return nil }
        return fractional.date(from: value) ?? plain.date(from: value)
    }
    private func lines(_ url: URL, matching markers: [String], consume: (Data) -> Void) -> Bool {
        guard let file = fopen(url.path, "r") else { return false }
        defer { fclose(file) }
        var line: UnsafeMutablePointer<CChar>?, capacity = 0
        defer { free(line) }
        while !Task.isCancelled {
            let n = getline(&line, &capacity, file)
            guard n >= 0, let line else { break }
            guard markers.isEmpty || markers.contains(where: { strstr(line, $0) != nil }) else { continue }
            consume(Data(bytesNoCopy: line, count: n, deallocator: .none))
        }
        return ferror(file) == 0
    }
    private func session(_ url: URL, task: String, created: Date) -> SessionData? {
        guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]), let modified = attrs.contentModificationDate, let size = attrs.fileSize else { return nil }
        if let saved = cache[url.path], saved.modified == modified, saved.size == size { return saved.data }
        var result = SessionData()
        var representations: [String: [(Date, String)]] = [:]
        let ok = lines(url, matching: ["\"task_started\"", "\"task_complete\"", "\"turn_aborted\"", "\"UserMessage\"", "\"user_message\"", "\"role\":\"user\"", "\"role\": \"user\""]) { data in
            guard let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let payload = row["payload"] as? [String: Any], let at = date(row["timestamp"]), at >= created,
                  payload["thread_id"] == nil || payload["thread_id"] as? String == task else { return }
            let type = payload["type"] as? String
            if let turn = payload["turn_id"] as? String {
                let key = task + ":" + turn
                if type == "task_started" { result.starts[key] = date(payload["started_at"]) ?? at }
                if type == "task_complete" || type == "turn_aborted" { result.ends[key] = date(payload["completed_at"]) ?? at }
            }
            let id: String
            let content: [[String: Any]]
            let messageAt: Date
            if type == "item_completed", let item = payload["item"] as? [String: Any], item["type"] as? String == "UserMessage", let itemID = item["id"] as? String, let parts = item["content"] as? [[String: Any]] {
                id = itemID; content = parts; messageAt = date(payload["completed_at_ms"]) ?? at
            } else if row["type"] as? String == "response_item", type == "message", payload["role"] as? String == "user", let parts = payload["content"] as? [[String: Any]] {
                id = "response:" + String(at.timeIntervalSince1970); content = parts; messageAt = at
            } else if type == "user_message", let text = payload["message"] as? String {
                id = "legacy:" + String(at.timeIntervalSince1970); content = [["type": "text", "text": text]]; messageAt = at
            } else { return }
            var text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
            for tag in ["environment_context", "in-app-browser-context", "recommended_plugins"] {
                // Dot-all is needed for ambient multi-line blocks.
                text = text.replacingOccurrences(of: "(?s)<\(tag)\\b[^>]*>.*?</\(tag)>", with: "", options: .regularExpression)
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !(text.isEmpty && content.allSatisfy { ["text", "input_text"].contains($0["type"] as? String ?? "") }),
                  !text.hasPrefix("# AGENTS.md instructions"), !text.hasPrefix("<permissions instructions>"),
                  text.range(of: "(?i)^(?:<heartbeat|<automation|Automation(?: name| ID|:)|\\[automation|<goal)", options: .regularExpression) == nil else { return }
            let fingerprint = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            let kind = id.hasPrefix("response:") ? "response" : id.hasPrefix("legacy:") ? "legacy" : "modern"
            // Reconcile different representations, while retaining repeated genuine messages.
            if representations[fingerprint, default: []].contains(where: { $0.1 != kind && abs($0.0.timeIntervalSince(messageAt)) < 120 }) { return }
            representations[fingerprint, default: []].append((messageAt, kind))
            result.messages[task + ":" + id] = PromptingMessage(at: messageAt, task: task)
        }
        guard ok else { return nil }
        cache[url.path] = Cache(modified: modified, size: size, data: result)
        return result
    }
    public func read(now: Date = Date(), calendar: Calendar = .current, codexRoot: URL = TokenHistory.defaultRoot().deletingLastPathComponent(), activityRoot: URL? = nil, screenTimeRoot: URL? = nil) -> PromptingSnapshot {
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        var messages: [String: PromptingMessage] = [:], starts: [String: Date] = [:], ends: [String: Date] = [:]
        var paths = Set<String>(), unavailable = 0, sessionsAvailable = false
        var contextTasks: [ContextTask] = []
        var db: OpaquePointer?
        if sqlite3_open_v2(codexRoot.appendingPathComponent("state_5.sqlite").path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let db {
            sqlite3_busy_timeout(db, 1000)
            var query: OpaquePointer?
            let sql = "SELECT id, rollout_path, COALESCE(name,title), created_at, cwd FROM threads WHERE updated_at >= ? AND thread_source = 'user' AND source NOT LIKE '{%'"
            if sqlite3_prepare_v2(db, sql, -1, &query, nil) == SQLITE_OK, let query {
                sqlite3_bind_int64(query, 1, Int64(start.timeIntervalSince1970))
                var status = sqlite3_step(query)
                while status == SQLITE_ROW {
                    func column(_ i: Int32) -> String { sqlite3_column_text(query, i).map { String(cString: $0) } ?? "" }
                    let task = column(0), url = URL(fileURLWithPath: column(1)), created = Date(timeIntervalSince1970: sqlite3_column_double(query, 3))
                    let title = String(column(2).components(separatedBy: .newlines).first?.prefix(100) ?? "Task")
                    if title.hasPrefix("[CoS]") || title.hasPrefix("Automation:") { status = sqlite3_step(query); continue }
                    contextTasks.append(ContextTask(id: task, title: title, context: ContextMetrics.suggestedContext(cwd: column(4), title: title)))
                    let siblings = (try? FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
                    let candidates = Set([url] + siblings.filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.contains(task) })
                    for path in candidates where paths.insert(path.path).inserted {
                        if let parsed = session(path, task: task, created: created) {
                            messages.merge(parsed.messages) { a, _ in a }; starts.merge(parsed.starts) { a, b in min(a,b) }; ends.merge(parsed.ends) { a, b in max(a,b) }
                        } else { unavailable += 1 }
                    }
                    status = sqlite3_step(query)
                }
                sessionsAvailable = status == SQLITE_DONE
                sqlite3_finalize(query)
            }
        }
        if let db { sqlite3_close(db) }
        cache = cache.filter { paths.contains($0.key) }
        let runs = starts.compactMap { key, begin -> PromptingRun? in
            guard let end = ends[key], end > begin else { return nil }
            return PromptingRun(start: begin, end: end, task: String(key.prefix(36)))
        }
        var days = PromptingMetrics.days(inputs: [], selections: [], messages: Array(messages.values), runs: runs, activityRange: nil, activityDates: [], sessionsAvailable: sessionsAvailable, now: now, calendar: calendar)
        let foreground = ScreenTimeHistory.readResult(root: screenTimeRoot, now: now, calendar: calendar)
        for i in days.indices { days[i].codexSeconds = foreground.seconds[days[i].date] }
        return PromptingSnapshot(days: days, updatedAt: now, sessionsAvailable: sessionsAvailable, incompleteRuns: starts.filter { $0.value >= start && ends[$0.key] == nil }.count, unreadableFiles: unavailable, screenTimeAccessDenied: foreground.accessDenied, contextTasks: contextTasks, contextMessages: Array(messages.values))
    }
}
