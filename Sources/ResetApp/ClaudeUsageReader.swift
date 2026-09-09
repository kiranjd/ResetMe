import Foundation
import LocalAuthentication
import ResetCore
import Security

enum ClaudeUsageReadError: LocalizedError {
    case credentialsUnavailable
    case credentialsMalformed
    case credentialsExpired
    case unauthorized
    case forbidden
    case rateLimited(Date?)
    case invalidResponse
    case serverUnavailable
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .credentialsUnavailable:
            "Open Claude Code and sign in, then try again."
        case .credentialsMalformed:
            "Claude Code’s saved sign-in couldn’t be read. Run `claude auth status`, then sign in again if needed."
        case .credentialsExpired:
            "Claude Code’s sign-in has expired. Open `claude` once to refresh it, then try again."
        case .unauthorized:
            "Claude rejected the saved sign-in. Open `claude` once to refresh it, then try again."
        case .forbidden:
            "Claude’s saved sign-in cannot read usage for this account."
        case let .rateLimited(retryAt):
            retryAt.map { "Claude is rate limiting usage checks until \($0.formatted(date: .omitted, time: .shortened))." }
                ?? "Claude is rate limiting usage checks. Try again in a few minutes."
        case .invalidResponse:
            "Claude returned usage in an unsupported format."
        case .serverUnavailable:
            "Claude usage is temporarily unavailable."
        case let .network(error):
            "Couldn’t reach Claude: \(error.localizedDescription)"
        }
    }
}

struct ClaudeUsageReader {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport

    init(transport: @escaping Transport = ClaudeUsageReader.liveTransport) {
        self.transport = transport
    }

    func fetch(environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> ProviderUsageSnapshot {
        try Task.checkCancellation()
        let token = try ClaudeCredentialReader.accessToken(environment: environment)
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        // Anthropic currently requires the Claude Code OAuth user agent for this endpoint.
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ClaudeUsageReadError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw ClaudeUsageReadError.invalidResponse }
        do {
            return try ClaudeUsageHTTPDecoder.snapshot(statusCode: http.statusCode, data: data)
        } catch let error as ClaudeUsageHTTPError {
            switch error {
            case .unauthorized: throw ClaudeUsageReadError.unauthorized
            case .forbidden: throw ClaudeUsageReadError.forbidden
            case .rateLimited: throw ClaudeUsageReadError.rateLimited(Self.retryDate(response: http))
            case .serverUnavailable: throw ClaudeUsageReadError.serverUnavailable
            case .invalidResponse: throw ClaudeUsageReadError.invalidResponse
            }
        } catch {
            throw ClaudeUsageReadError.invalidResponse
        }
    }

    private static func liveTransport(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }

    private static func retryDate(response: HTTPURLResponse, now: Date = Date()) -> Date? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
        else { return nil }
        if let seconds = TimeInterval(value), seconds >= 0 { return now.addingTimeInterval(seconds) }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return parser.date(from: value)
    }
}

private enum ClaudeCredentialReader {
    static func accessToken(environment: [String: String], now: Date = Date()) throws -> String {
        let customProfile = environment["CLAUDE_CONFIG_DIR"]?.isEmpty == false
        let fileURL = credentialsURL(environment: environment)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let data = try? Data(contentsOf: fileURL) else { throw ClaudeUsageReadError.credentialsUnavailable }
            return try parse(data, now: now)
        }
        // Claude's global Keychain item belongs only to its default profile.
        guard !customProfile else { throw ClaudeUsageReadError.credentialsUnavailable }
        guard let data = keychainDataWithoutUI() else { throw ClaudeUsageReadError.credentialsUnavailable }
        return try parse(data, now: now)
    }

    private static func parse(_ data: Data, now: Date) throws -> String {
        do {
            return try JSONDecoder().decode(ClaudeCredentialPayload.self, from: data).validatedAccessToken(now: now)
        } catch ClaudeCredentialPayloadError.expired {
            throw ClaudeUsageReadError.credentialsExpired
        } catch {
            throw ClaudeUsageReadError.credentialsMalformed
        }
    }

    private static func credentialsURL(environment: [String: String]) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func directory(_ value: String) -> URL {
            if value.hasPrefix("/") { return URL(fileURLWithPath: value, isDirectory: true) }
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent(value, isDirectory: true)
        }
        let defaultRoot = home.appendingPathComponent(".claude", isDirectory: true)
        let configRoot = environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : directory($0) } ?? defaultRoot
        let secureRoot = environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"].map { $0.isEmpty ? defaultRoot : directory($0) }
        return (secureRoot ?? configRoot).appendingPathComponent(".credentials.json")
    }

    private static func keychainDataWithoutUI() -> Data? {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }
}
