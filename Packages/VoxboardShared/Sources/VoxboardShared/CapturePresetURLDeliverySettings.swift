import Foundation

/// Per-preset HTTP delivery. Off unless the user enables it and supplies a URL.
///
/// The bearer token is deliberately *not* stored here. Only `hasBearerToken`
/// is persisted; the secret itself lives in the Keychain under
/// `URLDeliveryKeychain.service`.
public struct CapturePresetURLDeliverySettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var urlString: String
    public var hasBearerToken: Bool
    /// Extra request headers, e.g. an HMAC signature. Protocol-critical headers
    /// (`Content-Type`, `Idempotency-Key`) and a configured bearer token are
    /// enforced after these, so they cannot be overridden.
    public var customHeaders: [String: String]
    /// Keep writing the file sink (when configured) even if the URL delivery
    /// fails. A URL failure is independent and retryable.
    public var deliverOnFailureFallbackFile: Bool
    public var maxAttempts: Int
    /// Prefer `cleanedText` when present in the JSON body.
    public var includeCleanedText: Bool

    public init(
        enabled: Bool = false,
        urlString: String = "",
        hasBearerToken: Bool = false,
        customHeaders: [String: String] = [:],
        deliverOnFailureFallbackFile: Bool = true,
        maxAttempts: Int = 5,
        includeCleanedText: Bool = true
    ) {
        self.enabled = enabled
        self.urlString = urlString
        self.hasBearerToken = hasBearerToken
        self.customHeaders = customHeaders
        self.deliverOnFailureFallbackFile = deliverOnFailureFallbackFile
        self.maxAttempts = maxAttempts
        self.includeCleanedText = includeCleanedText
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case urlString
        case hasBearerToken
        case customHeaders
        case deliverOnFailureFallbackFile
        case maxAttempts
        case includeCleanedText
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        urlString = try container.decodeIfPresent(String.self, forKey: .urlString) ?? ""
        hasBearerToken = try container.decodeIfPresent(Bool.self, forKey: .hasBearerToken) ?? false
        customHeaders = try container.decodeIfPresent([String: String].self, forKey: .customHeaders) ?? [:]
        deliverOnFailureFallbackFile = try container.decodeIfPresent(Bool.self, forKey: .deliverOnFailureFallbackFile) ?? true
        maxAttempts = try container.decodeIfPresent(Int.self, forKey: .maxAttempts) ?? 5
        includeCleanedText = try container.decodeIfPresent(Bool.self, forKey: .includeCleanedText) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(urlString, forKey: .urlString)
        try container.encode(hasBearerToken, forKey: .hasBearerToken)
        try container.encode(customHeaders, forKey: .customHeaders)
        try container.encode(deliverOnFailureFallbackFile, forKey: .deliverOnFailureFallbackFile)
        try container.encode(maxAttempts, forKey: .maxAttempts)
        try container.encode(includeCleanedText, forKey: .includeCleanedText)
    }
}

/// Validation for a user-entered delivery URL and the rendered body.
public enum URLDeliveryValidationError: LocalizedError, Equatable, Sendable {
    case emptyURL
    case invalidURL
    case insecureScheme
    case insecureLocalRequiresConfirmation
    case credentialsInURL
    case queryStringSecret
    case missingHost
    case bodyTooLarge(Int)

    public var errorDescription: String? {
        switch self {
        case .emptyURL:
            return "Enter a delivery URL."
        case .invalidURL:
            return "That does not look like a valid URL."
        case .insecureScheme:
            return "Use HTTPS. Plain HTTP is only allowed for loopback or local-network addresses."
        case .insecureLocalRequiresConfirmation:
            return "Plain HTTP is insecure. Confirm that this is a local-only endpoint to continue."
        case .credentialsInURL:
            return "Remove the username or password from the URL. Put the secret in the token field instead."
        case .queryStringSecret:
            return "Do not put secrets in the URL query string. Use the token field instead."
        case .missingHost:
            return "The URL is missing a host."
        case .bodyTooLarge(let bytes):
            return "The transcript is too large to deliver (\(bytes) bytes; the limit is \(URLDeliveryValidator.maxBodyBytes) bytes)."
        }
    }
}

public enum URLDeliveryValidator {
    /// 1 MiB. A voice note body is normally well under this.
    public static let maxBodyBytes = 1 * 1024 * 1024

    /// Secret-looking query parameter names. Best-effort: the goal is to stop
    /// the obvious mistake, not to be a parser for every webhook convention.
    private static let secretQueryNames: Set<String> = [
        "token", "access_token", "api_key", "apikey", "key", "secret",
        "password", "passwd", "auth", "authorization", "signature", "sig",
    ]

    /// Validates a user-entered URL.
    ///
    /// - Parameter allowingInsecureLocal: pass `true` only after the user has
    ///   explicitly confirmed an "insecure, local only" endpoint.
    public static func validate(
        _ rawURLString: String,
        allowingInsecureLocal: Bool = false
    ) throws -> URL {
        let trimmed = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw URLDeliveryValidationError.emptyURL }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty,
              let url = components.url else {
            throw URLDeliveryValidationError.invalidURL
        }
        guard components.user == nil, components.password == nil else {
            throw URLDeliveryValidationError.credentialsInURL
        }
        if let queryItems = components.queryItems,
           queryItems.contains(where: { secretQueryNames.contains($0.name.lowercased()) }) {
            throw URLDeliveryValidationError.queryStringSecret
        }

        switch scheme {
        case "https":
            return url
        case "http":
            guard isLocalHost(host) else { throw URLDeliveryValidationError.insecureScheme }
            guard allowingInsecureLocal else {
                throw URLDeliveryValidationError.insecureLocalRequiresConfirmation
            }
            return url
        default:
            throw URLDeliveryValidationError.invalidURL
        }
    }

    /// True for loopback, `.local`, and RFC1918 / link-local literals.
    public static func isLocalHost(_ host: String) -> Bool {
        let lower = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if lower == "localhost" || lower == "::1" || lower == "0.0.0.0" { return true }
        if lower.hasSuffix(".local") { return true }
        let parts = lower.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        if parts[0] == 127 { return true }                       // loopback
        if parts[0] == 10 { return true }                        // RFC1918
        if parts[0] == 172, (16...31).contains(parts[1]) { return true }
        if parts[0] == 192, parts[1] == 168 { return true }
        if parts[0] == 169, parts[1] == 254 { return true }      // link-local
        return false
    }

    public static func validateBody(_ data: Data) throws {
        guard data.count <= maxBodyBytes else {
            throw URLDeliveryValidationError.bodyTooLarge(data.count)
        }
    }
}
