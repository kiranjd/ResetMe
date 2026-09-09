import Darwin
import Foundation

public enum ClaudeTokenHistory {
    public static func defaultRoots(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [URL] {
        var roots: [URL] = []
        if let configured = environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty {
            let url = configured.hasPrefix("/")
                ? URL(fileURLWithPath: configured, isDirectory: true)
                : URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                    .appendingPathComponent(configured, isDirectory: true)
            roots.append(url.appendingPathComponent("projects", isDirectory: true))
        } else {
            roots.append(home.appendingPathComponent(".config/claude/projects", isDirectory: true))
            roots.append(home.appendingPathComponent(".claude/projects", isDirectory: true))
            roots.append(home.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions", isDirectory: true))
        }
        var seen = Set<String>()
        return roots.map(\.standardizedFileURL).filter { seen.insert($0.path).inserted }
    }

    public static func days(
        roots: [URL],
        now: Date = Date(),
        calendar: Calendar = .current,
        dayCount: Int = 7
    ) -> [TokenDay] {
        struct Row {
            var timestamp: Date
            var model: String
            var input: Int
            var cached: Int
            var output: Int
            var total: Int
        }

        let count = max(1, dayCount)
        let start = calendar.date(byAdding: .day, value: -(count - 1), to: calendar.startOfDay(for: now))!
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        var keyed: [String: Row] = [:]
        var unkeyed: [Row] = []

        func integer(_ value: Any?) -> Int {
            max(0, (value as? NSNumber)?.intValue ?? 0)
        }
        func parse(_ data: Data, path: String) {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let stamp = object["timestamp"] as? String,
                  let date = fractional.date(from: stamp) ?? plain.date(from: stamp),
                  date >= start, date <= now,
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { return }
            let directInput = integer(usage["input_tokens"])
            let cacheCreate = integer(usage["cache_creation_input_tokens"])
            let cacheRead = integer(usage["cache_read_input_tokens"])
            let output = integer(usage["output_tokens"])
            let total = directInput + cacheCreate + cacheRead + output
            guard total > 0 else { return }
            let row = Row(
                timestamp: date,
                model: (message["model"] as? String) ?? "Claude",
                input: directInput + cacheCreate + cacheRead,
                cached: cacheRead,
                output: output,
                total: total)
            if let messageID = message["id"] as? String,
               let requestID = object["requestId"] as? String
            {
                let sessionID = (object["sessionId"] as? String) ?? path
                keyed["\(sessionID):\(messageID):\(requestID)"] = row
            } else {
                unkeyed.append(row)
            }
        }

        for root in roots {
            guard let files = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles])
            else { continue }
            while let url = files.nextObject() as? URL {
                guard url.pathExtension == "jsonl",
                      let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      modified >= start,
                      let file = fopen(url.path, "r")
                else { continue }
                defer { fclose(file) }
                var line: UnsafeMutablePointer<CChar>?
                var capacity = 0
                defer { free(line) }
                while true {
                    let byteCount = getline(&line, &capacity, file)
                    guard byteCount >= 0, let line else { break }
                    guard strstr(line, "\"type\":\"assistant\"") != nil,
                          strstr(line, "\"usage\"") != nil
                    else { continue }
                    parse(Data(bytesNoCopy: line, count: byteCount, deallocator: .none), path: url.path)
                }
            }
        }

        var totals: [Date: TokenDay] = [:]
        for row in Array(keyed.values) + unkeyed {
            let date = calendar.startOfDay(for: row.timestamp)
            var day = totals[date] ?? TokenDay(date: date, tokens: 0)
            day.tokens = (day.tokens ?? 0) + row.total
            day.input += row.input
            day.cached += row.cached
            day.output += row.output
            day.unpriced += row.total
            day.modelTokens[row.model, default: 0] += row.total
            totals[date] = day
        }
        return (0..<count).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            return totals[date] ?? TokenDay(date: date, tokens: nil)
        }
    }
}
