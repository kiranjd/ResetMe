import Foundation

/// Quota metadata only. Local conversation text never enters reset history.
public struct QuotaObservation: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable { case live, codexHistory }
    public var provider: UsageProvider
    public var bucketID: String
    public var bucketName: String
    public var durationMinutes: Int
    public var used: Double
    public var resetsAt: Double?
    public var timestamp: Date
    public var source: Source
    public var plan: String?
    public var key: String { "\(provider.rawValue)|\(bucketID)|\(durationMinutes)" }

    public init(provider: UsageProvider, bucketID: String, bucketName: String, durationMinutes: Int,
                used: Double, resetsAt: Double?, timestamp: Date, source: Source = .live, plan: String? = nil) {
        self.provider = provider; self.bucketID = bucketID; self.bucketName = bucketName
        self.durationMinutes = durationMinutes; self.used = used; self.resetsAt = resetsAt
        self.timestamp = timestamp; self.source = source; self.plan = plan
    }
    public static func snapshot(_ snapshot: ProviderUsageSnapshot, at date: Date) -> [Self] {
        snapshot.buckets.flatMap { bucket in
            bucket.windows.compactMap { window in
                guard let duration = window.windowDurationMins, duration == 10_080 else { return nil }
                return Self(provider: snapshot.provider, bucketID: bucket.id, bucketName: bucket.name,
                            durationMinutes: duration, used: window.usedPercent, resetsAt: window.resetsAt,
                            timestamp: date, plan: bucket.planType)
            }
        }
    }
    public static func codexRecord(_ limits: [String: Any], at date: Date) -> [Self] {
        let id = limits["limit_id"] as? String ?? "codex"
        guard CodexQuota.includes(id: id, name: limits["limit_name"] as? String ?? "") else { return [] }
        return ["primary", "secondary"].compactMap { slot in
            guard let window = limits[slot] as? [String: Any],
                  let used = window["used_percent"] as? Double,
                  let duration = window["window_minutes"] as? Int, duration == 10_080 else { return nil }
            return Self(provider: .codex, bucketID: id, bucketName: limits["limit_name"] as? String ?? (id == "codex" ? "Codex" : id),
                        durationMinutes: duration, used: used, resetsAt: window["resets_at"] as? Double,
                        timestamp: date, source: .codexHistory, plan: limits["plan_type"] as? String)
        }
    }
}

public struct QuotaResetEvent: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case scheduled, cycleRestart, allowanceRestored
        public var title: String {
            switch self {
            case .scheduled: "Scheduled reset"
            case .cycleRestart: "Unscheduled reset"
            case .allowanceRestored: "Allowance restored"
            }
        }
    }
    public var id: String
    public var provider: UsageProvider
    public var bucketID: String
    public var bucketName: String
    public var durationMinutes: Int
    public var kind: Kind
    /// Scheduled deadline, inferred cycle start, or first observation if timing is unknown.
    public var date: Date
    public var detectedAt: Date
    public var previousObservation: Date
    public var nextResetAt: Double?
    public var estimated: Bool
    public var windowName: String {
        switch durationMinutes {
        case 300: "5-hour"
        case 10_080: "Weekly"
        case 1440: "Daily"
        default: "\(durationMinutes / 60)-hour"
        }
    }
    public var explanation: String {
        switch kind {
        case .scheduled:
            "The provider's scheduled boundary passed and a later quota window was observed."
        case .cycleRestart:
            "Estimated from the new quota window's deadline and duration. The provider does not identify whether a person or the provider initiated it."
        case .allowanceRestored:
            "Usage decreased between observations without a confirmed cycle change. This may be a manual reset, credit, or provider correction; the exact time and cause are unavailable."
        }
    }
}

/// Durable events are separate from short-lived pace samples. Never synthesize recurring
/// resets during offline gaps, and never infer a manual action from a percentage alone.
public struct ResetHistory: Codable, Sendable {
    public private(set) var events: [QuotaResetEvent] = []
    private var baselines: [String: QuotaObservation] = [:]
    private static let deadlineTolerance: Double = 5
    public init() {}

    public mutating func observe(_ observations: [QuotaObservation]) {
        for current in observations.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard current.provider != .codex || CodexQuota.includes(id: current.bucketID, name: current.bucketName) else { continue }
            guard current.used.isFinite, (0...100).contains(current.used), current.durationMinutes == 10_080,
                  current.timestamp.timeIntervalSince1970.isFinite,
                  current.resetsAt.map({ $0.isFinite && $0 > 0 }) ?? true else { continue }
            // Expired cached records are not observations of the current window.
            if let end = current.resetsAt, end < current.timestamp.timeIntervalSince1970 - Self.deadlineTolerance { continue }
            guard let previous = baselines[current.key] else { baselines[current.key] = current; continue }
            guard current.timestamp > previous.timestamp else { continue }
            if let oldPlan = previous.plan, let newPlan = current.plan, oldPlan != newPlan {
                baselines[current.key] = current; continue
            }
            // Concurrent local sessions can keep emitting an old cached quota window.
            if let oldEnd = previous.resetsAt, let newEnd = current.resetsAt,
               newEnd < oldEnd - Self.deadlineTolerance { continue }
            if let event = Self.transition(from: previous, to: current) { merge([event]) }
            // Small timestamp jitter must not accumulate into an apparent new cycle.
            var baseline = current
            if let oldEnd = previous.resetsAt, let newEnd = current.resetsAt,
               abs(newEnd - oldEnd) <= Self.deadlineTolerance { baseline.resetsAt = oldEnd }
            baselines[current.key] = baseline
        }
    }

    public mutating func merge(_ incoming: [QuotaResetEvent]) {
        for event in incoming {
            guard event.provider != .codex || CodexQuota.includes(id: event.bucketID, name: event.bucketName) else { continue }
            if let index = events.firstIndex(where: { Self.sameReset($0, event) }) {
                let old = events[index]
                // Prefer a confirmed scheduled boundary, otherwise the earliest detection.
                if (old.kind == .allowanceRestored && event.kind != .allowanceRestored) || (old.estimated && !event.estimated) || (old.kind == event.kind && old.estimated == event.estimated && event.detectedAt < old.detectedAt) {
                    var replacement = event; replacement.id = old.id; events[index] = replacement
                }
            } else { events.append(event) }
        }
        events.sort { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }

    private static func sameReset(_ a: QuotaResetEvent, _ b: QuotaResetEvent) -> Bool {
        guard a.provider == b.provider, a.bucketID == b.bucketID, a.durationMinutes == b.durationMinutes else { return false }
        if a.kind == .allowanceRestored && b.kind == .allowanceRestored { return a.id == b.id }
        guard let aEnd = a.nextResetAt, let bEnd = b.nextResetAt else { return a.id == b.id }
        guard abs(aEnd - bEnd) <= deadlineTolerance else { return false }
        if a.kind == .allowanceRestored || b.kind == .allowanceRestored {
            let restoration = a.kind == .allowanceRestored ? a : b
            let cycle = a.kind == .allowanceRestored ? b : a
            return cycle.date >= restoration.previousObservation.addingTimeInterval(-deadlineTolerance)
                && cycle.date <= restoration.detectedAt.addingTimeInterval(deadlineTolerance)
        }
        return true
    }

    private static func transition(from before: QuotaObservation, to after: QuotaObservation) -> QuotaResetEvent? {
        let kind: QuotaResetEvent.Kind
        let date: Date
        let estimated: Bool
        if let oldEnd = before.resetsAt, let newEnd = after.resetsAt, newEnd > oldEnd + deadlineTolerance {
            let boundary = Date(timeIntervalSince1970: oldEnd)
            if boundary >= before.timestamp.addingTimeInterval(-deadlineTolerance), boundary <= after.timestamp {
                kind = .scheduled; date = boundary; estimated = false
            } else {
                let inferredStart = Date(timeIntervalSince1970: newEnd - Double(after.durationMinutes) * 60)
                // A future cycle start or an extension with no allowance restoration is
                // insufficient evidence of a reset. Do not stamp discovery time as fact.
                guard inferredStart <= after.timestamp,
                      inferredStart < boundary.addingTimeInterval(-deadlineTolerance),
                      after.used < before.used else { return nil }
                kind = .cycleRestart; date = inferredStart; estimated = true
            }
        } else if after.source == .live, before.source == .live, after.used < before.used {
            kind = .allowanceRestored; date = after.timestamp; estimated = true
        } else { return nil }
        let identity = kind == .allowanceRestored ? after.timestamp.timeIntervalSince1970 : (after.resetsAt ?? after.timestamp.timeIntervalSince1970)
        return QuotaResetEvent(id: "\(after.key)|\(kind.rawValue)|\(identity)", provider: after.provider,
            bucketID: after.bucketID, bucketName: after.bucketName, durationMinutes: after.durationMinutes,
            kind: kind, date: date, detectedAt: after.timestamp, previousObservation: before.timestamp,
            nextResetAt: after.resetsAt, estimated: estimated)
    }

    public static func recovered(from observations: [QuotaObservation]) -> [QuotaResetEvent] {
        var history = Self(); history.observe(observations); return history.events
    }
}

public struct ResetDay: Identifiable, Sendable {
    public var date: Date
    public var events: [QuotaResetEvent]
    public var id: Date { date }
    public static func groups(_ events: [QuotaResetEvent], provider: UsageProvider, start: Date, end: Date, calendar: Calendar = .current) -> [Self] {
        let filtered = events.filter { ($0.provider != .codex || CodexQuota.includes(id: $0.bucketID, name: $0.bucketName)) && $0.provider == provider && $0.durationMinutes == 10_080 && $0.date >= start && $0.date < end }
        return Dictionary(grouping: filtered, by: { calendar.startOfDay(for: $0.date) })
            .map { Self(date: $0.key, events: $0.value.sorted { $0.date < $1.date }) }
            .sorted { $0.date < $1.date }
    }
}
