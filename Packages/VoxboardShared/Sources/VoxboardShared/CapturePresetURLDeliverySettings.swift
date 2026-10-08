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
    /// In-memory headers only. Values are never encoded into presets or queues;
    /// the settings editor saves them in the Keychain under `credentialID`.
    public var customHeaders: [String: String]
    public var hasCustomHeaders: Bool
    /// An opaque, per-preset Keychain account, bound to this exact endpoint.
    public var credentialID: String?
    public var credentialURLString: String?
    /// Legacy PR archives containing plaintext headers / host-scoped tokens
    /// require the user to save credentials again before any network request.
    public var requiresCredentialMigration: Bool
    /// Explicit user consent, never inferred from a local-looking URL.
    public var allowingInsecureLocal: Bool
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
        includeCleanedText: Bool = true,
        hasCustomHeaders: Bool = false,
        credentialID: String? = nil,
        credentialURLString: String? = nil,
        requiresCredentialMigration: Bool = false,
        allowingInsecureLocal: Bool = false
    ) {
        self.enabled = enabled
        self.urlString = urlString
        self.hasBearerToken = hasBearerToken
        self.customHeaders = customHeaders
        self.hasCustomHeaders = hasCustomHeaders || !customHeaders.isEmpty
        self.credentialID = credentialID
        self.credentialURLString = credentialURLString
        self.requiresCredentialMigration = requiresCredentialMigration
        self.allowingInsecureLocal = allowingInsecureLocal
        self.deliverOnFailureFallbackFile = deliverOnFailureFallbackFile
        self.maxAttempts = maxAttempts
        self.includeCleanedText = includeCleanedText
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case urlString
        case hasBearerToken
        case customHeaders // decode legacy values only; never encode them
        case hasCustomHeaders
        case credentialID
        case credentialURLString
        case requiresCredentialMigration
        case allowingInsecureLocal
        case deliverOnFailureFallbackFile
        case maxAttempts
        case includeCleanedText
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        urlString = try container.decodeIfPresent(String.self, forKey: .urlString) ?? ""
        hasBearerToken = try container.decodeIfPresent(Bool.self, forKey: .hasBearerToken) ?? false
        let legacyHeaders = try container.decodeIfPresent([String: String].self, forKey: .customHeaders) ?? [:]
        customHeaders = [:]
        hasCustomHeaders = try container.decodeIfPresent(Bool.self, forKey: .hasCustomHeaders) ?? !legacyHeaders.isEmpty
        credentialID = try container.decodeIfPresent(String.self, forKey: .credentialID)
        credentialURLString = try container.decodeIfPresent(String.self, forKey: .credentialURLString)
        requiresCredentialMigration = (try container.decodeIfPresent(Bool.self, forKey: .requiresCredentialMigration) ?? false)
            || !legacyHeaders.isEmpty
            || ((hasBearerToken || hasCustomHeaders) && credentialID == nil)
        allowingInsecureLocal = try container.decodeIfPresent(Bool.self, forKey: .allowingInsecureLocal) ?? false
        deliverOnFailureFallbackFile = try container.decodeIfPresent(Bool.self, forKey: .deliverOnFailureFallbackFile) ?? true
        maxAttempts = try container.decodeIfPresent(Int.self, forKey: .maxAttempts) ?? 5
        includeCleanedText = try container.decodeIfPresent(Bool.self, forKey: .includeCleanedText) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(urlString, forKey: .urlString)
        try container.encode(hasBearerToken, forKey: .hasBearerToken)
        try container.encode(hasCustomHeaders || !customHeaders.isEmpty, forKey: .hasCustomHeaders)
        try container.encodeIfPresent(credentialID, forKey: .credentialID)
        try container.encodeIfPresent(credentialURLString, forKey: .credentialURLString)
        try container.encode(requiresCredentialMigration, forKey: .requiresCredentialMigration)
        try container.encode(allowingInsecureLocal, forKey: .allowingInsecureLocal)
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
    case invalidHeaders
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
        case .invalidHeaders:
            return "Use valid, unique HTTP header names and single-line values. Host, cookies, and connection headers are not allowed (16 KiB maximum)."
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
              !host.contains(where: { $0.isWhitespace }),
              components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true,
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
        let octets = lower.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4,
              octets.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return false }
        let parts = octets.compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        if parts[0] == 127 { return true }                       // loopback
        if parts[0] == 10 { return true }                        // RFC1918
        if parts[0] == 172, (16...31).contains(parts[1]) { return true }
        if parts[0] == 192, parts[1] == 168 { return true }
        if parts[0] == 169, parts[1] == 254 { return true }      // link-local
        return false
    }

    public static func validateHeaders(_ headers: [String: String]) throws {
        let tokenCharacters = Set("!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)
        let forbidden: Set<String> = [
            "host", "content-length", "transfer-encoding", "connection", "te", "trailer",
            "upgrade", "proxy-authorization", "proxy-connection", "cookie", "set-cookie",
        ]
        var names: Set<String> = []
        var byteCount = 0
        guard headers.count <= 32 else { throw URLDeliveryValidationError.invalidHeaders }
        for (name, value) in headers {
            let lower = name.lowercased()
            guard !name.isEmpty, name.utf8.count <= 128,
                  name.utf8.allSatisfy(tokenCharacters.contains),
                  names.insert(lower).inserted, !forbidden.contains(lower),
                  value.utf8.allSatisfy({ $0 >= 32 && $0 != 127 }) else {
                throw URLDeliveryValidationError.invalidHeaders
            }
            byteCount += name.utf8.count + value.utf8.count
            guard byteCount <= 16 * 1024 else { throw URLDeliveryValidationError.invalidHeaders }
        }
    }

    public static func validateBody(_ data: Data) throws {
        guard data.count <= maxBodyBytes else {
            throw URLDeliveryValidationError.bodyTooLarge(data.count)
        }
    }
}

/// Redact only the known preset snapshot in a validated queue/handoff archive.
/// Keep unknown metadata and capture state intact; never sweep arbitrary JSON.
enum URLDeliveryLegacyArchive {
    static func scrub(_ data: Data, at url: URL) throws {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if var job = root["job"] as? [String: Any] {
            guard redactDelivery(in: &job) else { return }
            root["job"] = job
        } else {
            guard redactDelivery(in: &root) else { return }
        }
        let redacted = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try redacted.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func redactDelivery(in archive: inout [String: Any]) -> Bool {
        guard var delivery = archive["delivery"] as? [String: Any],
              var associated = delivery["preset"] as? [String: Any],
              var preset = associated["_0"] as? [String: Any],
              var export = preset["exportSettings"] as? [String: Any],
              var settings = export["urlDelivery"] as? [String: Any],
              let headers = settings["customHeaders"] as? [String: String], !headers.isEmpty else { return false }
        settings.removeValue(forKey: "customHeaders")
        settings["hasCustomHeaders"] = true
        settings["requiresCredentialMigration"] = true
        export["urlDelivery"] = settings
        preset["exportSettings"] = export
        associated["_0"] = preset
        delivery["preset"] = associated
        archive["delivery"] = delivery
        return true
    }
}
