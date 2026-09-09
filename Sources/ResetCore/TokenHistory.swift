import Foundation
import Darwin

public struct TokenDay: Identifiable, Sendable {
    public var date: Date
    public var tokens: Int?
    public var id: Date { date }
    public var input = 0
    public var cached = 0
    public var output = 0
    public var unpriced = 0
    public var inputCost = 0.0
    public var cachedCost = 0.0
    public var outputCost = 0.0
    public var modelTokens: [String: Int] = [:]
    public var topModel: String? { modelTokens.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.first?.key }
    public var pricedTokens = 0
    public var cost: Double? { pricedTokens > 0 ? inputCost + cachedCost + outputCost : nil }
    public var uncached: Int { max(0, input - cached) }
}
public enum TokenHistory {
    public static func defaultRoot(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) -> URL {
        let configured = environment["CODEX_HOME"]
        let root: URL
        if let configured, !configured.isEmpty {
            root = configured.hasPrefix("/")
                ? URL(fileURLWithPath: configured, isDirectory: true)
                : workingDirectory.appendingPathComponent(configured, isDirectory: true)
        } else {
            root = home.appendingPathComponent(".codex", isDirectory: true)
        }
        return root.standardizedFileURL.appendingPathComponent("sessions", isDirectory: true)
    }

    public static func days(root: URL, now: Date = Date(), calendar: Calendar = .current, dayCount: Int = 7) -> [TokenDay] {
        let start = calendar.date(byAdding: .day, value: -(max(1, dayCount) - 1), to: calendar.startOfDay(for: now))!
        var totals: [Date: TokenDay] = [:]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        var seen = Set<String>()
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "jsonl", let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified >= start else { continue }
            let key = String(url.deletingPathExtension().lastPathComponent.suffix(36))
            guard seen.insert(key).inserted, let file = fopen(url.path, "r") else { continue }
            defer { fclose(file) }
            var previous: [String: Int]?
            var model: String?
            func consume(_ data: Data) {
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let payload = obj["payload"] as? [String: Any] else { return }
                if obj["type"] as? String == "turn_context" { model = payload["model"] as? String; return }
                guard obj["type"] as? String == "event_msg", payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any], let usage = info["total_token_usage"] as? [String: Int],
                      let total = usage["total_tokens"], let stamp = obj["timestamp"] as? String,
                      let date = formatter.date(from: stamp) ?? plain.date(from: stamp) else { return }
                let last = info["last_token_usage"] as? [String: Int] ?? [:]
                let old = previous; previous = usage
                let reset = old == nil || total < (old?["total_tokens"] ?? 0)
                func delta(_ key: String) -> Int { max(0, reset ? last[key] ?? 0 : (usage[key] ?? 0) - (old?[key] ?? 0)) }
                let count = delta("total_tokens")
                guard date >= start, date <= now else { return }
                let dateKey = calendar.startOfDay(for: date)
                var day = totals[dateKey] ?? TokenDay(date: dateKey, tokens: 0)
                day.tokens = (day.tokens ?? 0) + count
                if let model, count > 0, count == last["total_tokens"] {
                    day.modelTokens[model, default: 0] += count
                }
                let input = delta("input_tokens"), cached = min(input, delta("cached_input_tokens")), output = delta("output_tokens")
                day.input += input; day.cached += cached; day.output += output
                // Standard API-equivalent text estimate, not subscription spend.
                // Cache-write and service-tier adjustments are absent from local counters.
                let rates: [String: (Double, Double, Double)] = [
                    "gpt-6-astra": (10, 1, 50), "gpt-5.6-sol": (4, 0.4, 20),
                    "gpt-5.6": (4, 0.4, 20), "gpt-5.6-terra": (2, 0.2, 12), "gpt-5.6-luna": (0.2, 0.02, 1.2)
                ]
                // A gap spanning several requests cannot reliably resolve long-context pricing.
                if let model, let rate = rates[model], count > 0,
                   count == last["total_tokens"], input + output == count,
                   last["input_tokens"] != nil, usage["cached_input_tokens"] != nil {
                    let long = (last["input_tokens"] ?? 0) > 272_000
                    day.inputCost += Double(input - cached) * rate.0 * (long ? 2 : 1) / 1_000_000
                    day.cachedCost += Double(cached) * rate.1 * (long && model == "gpt-6-astra" ? 2 : 1) / 1_000_000
                    day.outputCost += Double(output) * rate.2 * (long ? 1.5 : 1) / 1_000_000
                    day.pricedTokens += count
                } else { day.unpriced += count }
                totals[dateKey] = day
            }
            // getline scans each byte once, even for large image/tool records.
            // Inspect bytes before decoding; only token-counter records become JSON.
            var line: UnsafeMutablePointer<CChar>?
            var capacity = 0
            defer { free(line) }
            while true {
                let count = getline(&line, &capacity, file)
                guard count >= 0, let line else { break }
                guard strstr(line, "\"token_count\"") != nil || strstr(line, "\"turn_context\"") != nil else { continue }
                consume(Data(bytesNoCopy: line, count: count, deallocator: .none))
            }
        }
        return (0..<max(1, dayCount)).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            return totals[date] ?? TokenDay(date: date, tokens: nil)
        }
    }
}
