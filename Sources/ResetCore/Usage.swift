import Foundation
import CoreGraphics

public enum UsageProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claude

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }
}

public struct LimitWindow: Codable, Equatable, Sendable {
    public var usedPercent: Double
    public var windowDurationMins: Int?
    public var resetsAt: Double?
    public var remaining: Double { max(0, min(100, 100 - usedPercent)) }
    public var name: String {
        guard let mins = windowDurationMins else { return "Allowance" }
        if mins == 10080 { return "Weekly" }
        if mins == 300 { return "5-hour" }
        if mins == 1440 { return "Daily" }
        return mins >= 60 ? "\(mins / 60)-hour" : "\(mins)-minute"
    }
    public var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
    public init(usedPercent: Double, windowDurationMins: Int?, resetsAt: Double?) {
        self.usedPercent = usedPercent; self.windowDurationMins = windowDurationMins; self.resetsAt = resetsAt
    }
}
public struct LimitBucket: Codable, Identifiable, Sendable {
    public var limitId: String?
    public var limitName: String?
    public var primary: LimitWindow?
    public var secondary: LimitWindow?
    public var planType: String?
    public var id: String { limitId ?? "codex" }
    public var name: String { limitName ?? "Codex" }
    public var windows: [LimitWindow] { [primary, secondary].compactMap { $0 } }
    public var constraining: LimitWindow? { windows.min { $0.remaining < $1.remaining } }
    public init(limitId: String?, limitName: String?, primary: LimitWindow?, secondary: LimitWindow?, planType: String?) {
        self.limitId = limitId
        self.limitName = limitName
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
    }
}
public struct ResetCredit: Codable, Sendable {
    public var expiresAt: Double?
    public var status: String?
}
public struct ResetCredits: Codable, Sendable {
    public var availableCount: Int?
    public var credits: [ResetCredit]?
    public var nextExpiry: Date? {
        credits?.filter { $0.status == "available" }.compactMap(\.expiresAt).min().map(Date.init(timeIntervalSince1970:))
    }
}

public struct ProviderUsageSnapshot: Sendable {
    public var provider: UsageProvider
    public var buckets: [LimitBucket]
    public var credits: ResetCredits?

    public init(provider: UsageProvider, buckets: [LimitBucket], credits: ResetCredits? = nil) {
        self.provider = provider
        self.buckets = buckets
        self.credits = credits
    }
}

/// The display APIs report a camera exclusion region, not a fixed notch size.
public struct NotchGeometry: Equatable {
    public var frame: CGRect
    public var cutoutWidth: CGFloat
    public var cutoutHeight: CGFloat
    /// Invisible activation anchor for a display without a hardware notch.
    public init(hoverScreenFrame: CGRect) {
        cutoutWidth = 200
        cutoutHeight = 24
        frame = CGRect(x: hoverScreenFrame.midX - 107, y: hoverScreenFrame.maxY - 31, width: 214, height: 31)
    }
    public init?(screenFrame: CGRect, safeTop: CGFloat, leftArea: CGRect?, rightArea: CGRect?) {
        guard safeTop > 0, let leftArea, let rightArea, rightArea.minX > leftArea.maxX else { return nil }
        cutoutWidth = rightArea.minX - leftArea.maxX
        cutoutHeight = safeTop
        frame = CGRect(x: leftArea.maxX - 7, y: screenFrame.maxY - safeTop - 7, width: cutoutWidth + 14, height: safeTop + 7)
    }
}
public enum CodexQuota {
    /// Ignore the retired separate Spark allowance at every reporting boundary.
    public static func includes(id: String, name: String = "") -> Bool {
        !id.localizedCaseInsensitiveContains("spark") && !name.localizedCaseInsensitiveContains("spark")
    }
}

public struct UsageResponse: Decodable, Sendable {
    public var rateLimits: LimitBucket?
    public var rateLimitsByLimitId: [String: LimitBucket]?
    public var rateLimitResetCredits: ResetCredits?
    public var buckets: [LimitBucket] {
        let items: [LimitBucket]
        if let map = rateLimitsByLimitId, !map.isEmpty { items = Array(map.values) }
        else { items = rateLimits.map { [$0] } ?? [] }
        return items.filter { CodexQuota.includes(id: $0.id, name: $0.name) }.sorted {
            if $0.id == "codex" { return $1.id != "codex" }
            if $1.id == "codex" { return false }
            return $0.name < $1.name
        }
    }
}
public struct UsageSample: Codable, Identifiable, Sendable {
    public var timestamp: Date
    public var used: Double
    public var resetAt: Double?
    public var bucketID: String
    public var id: Date { timestamp }
    public init(timestamp: Date, used: Double, resetAt: Double?, bucketID: String) {
        self.timestamp = timestamp; self.used = used; self.resetAt = resetAt; self.bucketID = bucketID
    }
}
public enum UsageSampling {
    /// Keeps the constraining-window pace series separate from the weekly reset-marker series.
    public static func samples(from buckets: [LimitBucket], timestamp: Date) -> [UsageSample] {
        buckets.flatMap { bucket in
            var result: [UsageSample] = []
            if let window = bucket.constraining {
                result.append(UsageSample(
                    timestamp: timestamp,
                    used: window.usedPercent,
                    resetAt: window.resetsAt,
                    bucketID: bucket.id))
            }
            if let weekly = bucket.windows.first(where: { $0.windowDurationMins == 10_080 }) {
                result.append(UsageSample(
                    timestamp: timestamp,
                    used: weekly.usedPercent,
                    resetAt: weekly.resetsAt,
                    bucketID: bucket.id + ":weekly"))
            }
            return result
        }
    }
}
public enum UsageMath {
    public static func pointsPerHour(samples: [UsageSample], bucketID: String, resetAt: Double?) -> Double? {
        let values = samples.filter { $0.bucketID == bucketID && $0.resetAt == resetAt }.sorted { $0.timestamp < $1.timestamp }
        guard let first = values.first, let last = values.last else { return nil }
        let elapsed = last.timestamp.timeIntervalSince(first.timestamp)
        guard elapsed >= 600, last.used >= first.used else { return nil }
        // A decrease signals replenishment or a provider correction; do not forecast across it.
        guard zip(values, values.dropFirst()).allSatisfy({ $1.used >= $0.used }) else { return nil }
        return (last.used - first.used) / elapsed * 3600
    }
    public static func comparison(amount: Double, unitPrice: Double) -> Double? {
        guard amount.isFinite, unitPrice.isFinite, amount >= 0, unitPrice > 0 else { return nil }
        return amount / unitPrice
    }
}

public enum PlanLabel {
    public static func format(_ raw: String) -> String {
        let normalized = raw.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        let words = normalized.split(separator: " ")
        if words.first == "pro", let tier = words.last, ["5x", "10x", "20x"].contains(String(tier)) {
            return "Pro " + tier.replacingOccurrences(of: "x", with: "×")
        }
        if normalized == "prolite" { return "Pro Lite" }
        return normalized.capitalized
    }
}
