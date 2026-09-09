import Foundation

public enum ClaudeUsagePayloadError: Error, Equatable {
    case noUsableLimits
}

public enum ClaudeUsageHTTPError: Error, Equatable {
    case unauthorized
    case forbidden
    case rateLimited
    case serverUnavailable
    case invalidResponse
}

public enum ClaudeUsageHTTPDecoder {
    public static func snapshot(statusCode: Int, data: Data) throws -> ProviderUsageSnapshot {
        switch statusCode {
        case 200:
            do { return try JSONDecoder().decode(ClaudeUsagePayload.self, from: data).snapshot() }
            catch { throw ClaudeUsageHTTPError.invalidResponse }
        case 401: throw ClaudeUsageHTTPError.unauthorized
        case 403: throw ClaudeUsageHTTPError.forbidden
        case 429: throw ClaudeUsageHTTPError.rateLimited
        case 500...599: throw ClaudeUsageHTTPError.serverUnavailable
        default: throw ClaudeUsageHTTPError.invalidResponse
        }
    }
}

public enum ClaudeCredentialPayloadError: Error, Equatable {
    case malformed
    case expired
}

public struct ClaudeCredentialPayload: Decodable, Sendable {
    private struct OAuth: Decodable, Sendable {
        var accessToken: String?
        var expiresAt: Double?
    }
    private var claudeAiOauth: OAuth?

    public func validatedAccessToken(now: Date = Date()) throws -> String {
        guard let oauth = claudeAiOauth,
              let token = oauth.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty,
              let expiry = oauth.expiresAt
        else { throw ClaudeCredentialPayloadError.malformed }
        guard Date(timeIntervalSince1970: expiry / 1000) > now else {
            throw ClaudeCredentialPayloadError.expired
        }
        return token
    }
}

public struct ClaudeUsagePayload: Decodable, Sendable {
    public struct Window: Decodable, Sendable {
        public var utilization: Double?
        public var resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    public struct ScopedLimit: Decodable, Sendable {
        public struct Scope: Decodable, Sendable {
            public struct Model: Decodable, Sendable {
                public var id: String?
                public var displayName: String?

                enum CodingKeys: String, CodingKey {
                    case id
                    case displayName = "display_name"
                }
            }

            public var model: Model?
        }

        public var kind: String?
        public var group: String?
        public var percent: Double?
        public var resetsAt: String?
        public var scope: Scope?

        enum CodingKeys: String, CodingKey {
            case kind, group, percent, scope
            case resetsAt = "resets_at"
        }
    }

    public var fiveHour: Window?
    public var sevenDay: Window?
    public var sevenDaySonnet: Window?
    public var sevenDayOpus: Window?
    public var limits: [ScopedLimit]?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case limits
    }

    public func snapshot() throws -> ProviderUsageSnapshot {
        let primary = makeWindow(fiveHour, duration: 300)
        let weekly = makeWindow(sevenDay, duration: 10_080)
        var buckets: [LimitBucket] = []
        if primary != nil || weekly != nil {
            buckets.append(LimitBucket(
                limitId: "claude",
                limitName: "Claude",
                primary: primary ?? weekly,
                secondary: primary == nil ? nil : weekly,
                planType: nil))
        }

        let legacyModels: [(String, String, Window?)] = [
            ("claude-sonnet", "Sonnet", sevenDaySonnet),
            ("claude-opus", "Opus", sevenDayOpus),
        ]
        for (id, name, payload) in legacyModels {
            guard let window = makeWindow(payload, duration: 10_080) else { continue }
            buckets.append(LimitBucket(limitId: id, limitName: name, primary: window, secondary: nil, planType: nil))
        }

        var seen = Set(buckets.map(\.id))
        for entry in limits ?? [] {
            guard entry.kind == "weekly_scoped", entry.group == "weekly" else { continue }
            guard let window = makeWindow(percent: entry.percent, reset: entry.resetsAt, duration: 10_080) else { continue }
            guard let displayName = entry.scope?.model?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !displayName.isEmpty,
                  displayName.localizedCaseInsensitiveCompare("All models") != .orderedSame
            else { continue }
            let rawID = entry.scope?.model?.id ?? displayName
            let slug = rawID.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
            let id = "claude-weekly-scoped-" + String(slug).split(separator: "-").joined(separator: "-")
            guard seen.insert(id).inserted else { continue }
            buckets.append(LimitBucket(
                limitId: id,
                limitName: "\(displayName) only",
                primary: window,
                secondary: nil,
                planType: nil))
        }

        guard !buckets.isEmpty else { throw ClaudeUsagePayloadError.noUsableLimits }
        return ProviderUsageSnapshot(provider: .claude, buckets: buckets)
    }

    private func makeWindow(_ value: Window?, duration: Int) -> LimitWindow? {
        makeWindow(percent: value?.utilization, reset: value?.resetsAt, duration: duration)
    }

    private func makeWindow(percent: Double?, reset: String?, duration: Int) -> LimitWindow? {
        guard let percent, percent.isFinite else { return nil }
        return LimitWindow(
            usedPercent: percent,
            windowDurationMins: duration,
            resetsAt: Self.parseDate(reset)?.timeIntervalSince1970)
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
