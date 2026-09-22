import Foundation
import OSLog

/// Reads this Mac's retained Screen Time focus transitions; never combines remote devices.
/// Apple's private Biome format may change, so unsupported/unreadable data stays unavailable.
public enum ScreenTimeHistory {
    struct Event: Hashable {
        var at: Date
        var bundle: String
        var foreground: Bool
    }

    public struct ReadResult {
        public var seconds: [Date: Double]
        public var accessDenied: Bool = false
    }

    public static func read(root: URL? = nil, now: Date = Date(), calendar: Calendar = .current) -> [Date: Double] {
        readResult(root: root, now: now, calendar: calendar).seconds
    }

    public static func readResult(root: URL? = nil, now: Date = Date(), calendar: Calendar = .current) -> ReadResult {
        let directory = root ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Biome/streams/restricted/App.InFocus/local")
        let logger = Logger(subsystem: "local.jd.reset", category: "ScreenTime")
        let files: [URL]
        do { files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) }
        catch { let error = error as NSError; logger.error("Screen Time directory read failed: domain=\(error.domain, privacy: .public) code=\(error.code)"); return ReadResult(seconds: [:], accessDenied: error.code == NSFileReadNoPermissionError || (error.domain == NSPOSIXErrorDomain && [1, 13].contains(error.code))) }
        var events = Set<Event>()
        for file in files where !file.lastPathComponent.hasPrefix(".") {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let data: Data
            do { data = try Data(contentsOf: file) }
            catch { let error = error as NSError; logger.error("Screen Time file read failed: domain=\(error.domain, privacy: .public) code=\(error.code)"); return ReadResult(seconds: [:], accessDenied: error.code == NSFileReadNoPermissionError || (error.domain == NSPOSIXErrorDomain && [1, 13].contains(error.code))) }
            for payload in records(Array(data)) {
                if let event = decode(payload), event.at <= now { events.insert(event) }
            }
        }
        logger.notice("Screen Time scan: files=\(files.count) decodedEvents=\(events.count)")
        return ReadResult(seconds: totals(Array(events), now: now, calendar: calendar))
    }

    static func totals(_ events: [Event], now: Date, calendar: Calendar) -> [Date: Double] {
        let firstDay = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        let ordered = Set(events).filter { $0.at <= now }.sorted {
            if $0.at != $1.at { return $0.at < $1.at }
            // Process loss before gain at the same timestamp.
            if $0.foreground != $1.foreground { return !$0.foreground }
            return $0.bundle < $1.bundle
        }
        var result: [Date: Double] = [:]
        for event in ordered where event.at >= firstDay { result[calendar.startOfDay(for: event.at)] = 0 }
        var current: Event?
        func add(_ start: Date, _ end: Date) {
            var at = max(start, firstDay)
            while at < end {
                let day = calendar.startOfDay(for: at)
                let next = min(end, calendar.date(byAdding: .day, value: 1, to: day)!)
                result[day, default: 0] += next.timeIntervalSince(at)
                at = next
            }
        }
        for event in ordered {
            if event.foreground {
                if current?.bundle == event.bundle { continue }
                if let current, current.bundle == "com.openai.codex" { add(current.at, event.at) }
                current = event
            } else if current?.bundle == event.bundle {
                if let current, current.bundle == "com.openai.codex" { add(current.at, event.at) }
                current = nil
            }
        }
        // An unmatched gain is not evidence the app stayed active until now.
        return result
    }

    private static func integer(_ bytes: [UInt8], _ offset: Int, _ size: Int) -> UInt64? {
        guard offset >= 0, size <= 8, offset <= bytes.count - size else { return nil }
        return (0..<size).reduce(UInt64(0)) { $0 | UInt64(bytes[offset + $1]) << ($1 * 8) }
    }

    static func records(_ bytes: [UInt8]) -> [[UInt8]] {
        let magic = Array("SEGB".utf8)
        var result: [[UInt8]] = []
        if bytes.count >= 56, Array(bytes[52..<56]) == magic {
            guard let limit = integer(bytes, 0, 4), limit <= bytes.count else { return [] }
            var at = 56
            while at + 32 <= Int(limit) {
                guard let size = integer(bytes, at, 4), size > 0, size <= 32 * 1024 * 1024 else { break }
                let end = at + 32 + Int(size)
                guard end <= Int(limit) else { break }
                result.append(Array(bytes[(at + 32)..<end]))
                at = (end + 7) / 8 * 8
            }
        } else if bytes.count >= 32, Array(bytes[0..<4]) == magic {
            guard let count = integer(bytes, 4, 4), count > 0, count <= 2_000_000 else { return [] }
            let trailer = bytes.count - Int(count) * 16
            guard trailer >= 32 else { return [] }
            var entries: [(Int, UInt64)] = []
            for i in 0..<Int(count) {
                guard let end = integer(bytes, trailer + i * 16, 4), let state = integer(bytes, trailer + i * 16 + 4, 4) else { return [] }
                entries.append((Int(end), state))
            }
            var at = 32
            for (offset, state) in entries.sorted(by: { $0.0 < $1.0 }) where state != 4 {
                let end = offset + 32
                guard end > at + 8, end <= trailer else { break }
                result.append(Array(bytes[(at + 8)..<end]))
                at = (end + 3) / 4 * 4
            }
        }
        return result
    }

    static func decode(_ bytes: [UInt8]) -> Event? {
        var at = 0, timestamp: Double?, bundle: String?, foreground: Bool?
        func varint() -> UInt64? {
            var value: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                guard at < bytes.count else { return nil }
                let byte = bytes[at]; at += 1
                if shift == 63 && byte > 1 { return nil }
                value |= UInt64(byte & 127) << shift
                if byte & 128 == 0 { return value }
            }
            return nil
        }
        while at < bytes.count {
            guard let key = varint(), key > 0 else { return nil }
            let field = key >> 3
            switch key & 7 {
            case 0:
                guard let value = varint() else { return nil }
                if field == 3 { foreground = value != 0 }
            case 1:
                guard let value = integer(bytes, at, 8) else { return nil }
                if field == 4 { timestamp = Double(bitPattern: value) }
                at += 8
            case 2:
                guard let length = varint(), length <= bytes.count - at else { return nil }
                if field == 6 { bundle = String(bytes: bytes[at..<(at + Int(length))], encoding: .utf8) }
                at += Int(length)
            case 5:
                guard at + 4 <= bytes.count else { return nil }; at += 4
            default: return nil
            }
        }
        guard let timestamp, timestamp.isFinite, timestamp >= 0, let bundle, !bundle.isEmpty, let foreground else { return nil }
        return Event(at: Date(timeIntervalSinceReferenceDate: timestamp), bundle: bundle, foreground: foreground)
    }
}
