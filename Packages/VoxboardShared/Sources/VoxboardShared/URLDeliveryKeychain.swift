import Foundation
import Security

/// Bearer tokens AND custom header values are Keychain-only. Each preset has
/// its own opaque account; credentials are bound to an exact validated URL.
public enum URLDeliveryKeychain {
    public static let service = "bontecou.Voxboard.urldelivery"

    public struct Credentials: Codable, Equatable, Sendable {
        public var urlString: String
        public var bearerToken: String?
        public var customHeaders: [String: String]

        public init(urlString: String, bearerToken: String? = nil, customHeaders: [String: String] = [:]) {
            self.urlString = urlString
            self.bearerToken = bearerToken
            self.customHeaders = customHeaders
        }
    }

    public enum StorageError: LocalizedError, Equatable, Sendable {
        case unavailable(Int32)
        case invalidData
        case missingCredentials
        case destinationChanged

        public var errorDescription: String? {
            switch self {
            case .unavailable(let status):
                "URL delivery credentials could not be accessed in the Keychain (\(status))."
            case .invalidData:
                "The saved URL delivery credentials are invalid. Save them again."
            case .missingCredentials:
                "The saved URL delivery credentials are unavailable. Save them again before sending."
            case .destinationChanged:
                "The delivery URL changed. Save credentials for this endpoint before sending."
            }
        }
    }

    public static func credentials(forID id: String) throws -> Credentials? {
        try Store(client: .live).load(id: id)
    }

    public static func saveCredentials(_ credentials: Credentials, forID id: String) throws {
        try Store(client: .live).save(credentials, id: id)
    }

    public static func deleteCredentials(forID id: String) throws {
        try Store(client: .live).delete(id: id)
    }

    /// Never falls back to PR #35's host-scoped account: that could share one
    /// preset's token with another endpoint on the same host.
    static func token(forID id: String) throws -> String? {
        try credentials(forID: id)?.bearerToken
    }

    static func headers(forID id: String) throws -> [String: String]? {
        try credentials(forID: id)?.customHeaders
    }

    /// A narrow Security.framework boundary so error paths can be tested
    /// without touching the user's real Keychain.
    struct Client {
        var load: (String) -> (OSStatus, Data?)
        var update: (String, Data) -> OSStatus
        var add: (String, Data) -> OSStatus
        var delete: (String) -> OSStatus

        private static func query(_ id: String) -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: id,
            ]
        }

        static var live: Client {
            Client(
                load: { id in
                    var query = query(id)
                    query[kSecReturnData as String] = true
                    query[kSecMatchLimit as String] = kSecMatchLimitOne
                    var item: CFTypeRef?
                    let status = SecItemCopyMatching(query as CFDictionary, &item)
                    return (status, item as? Data)
                },
                update: { id, data in
                    SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
                },
                add: { id, data in
                    var query = query(id)
                    query[kSecValueData as String] = data
                    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                    query[kSecAttrSynchronizable as String] = false
                    return SecItemAdd(query as CFDictionary, nil)
                },
                delete: { SecItemDelete(query($0) as CFDictionary) }
            )
        }
    }

    struct Store {
        var client: Client

        func load(id: String) throws -> Credentials? {
            guard UUID(uuidString: id) != nil else { throw StorageError.missingCredentials }
            let (status, data) = client.load(id)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess else { throw StorageError.unavailable(status) }
            guard let data, let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else {
                throw StorageError.invalidData
            }
            return credentials
        }

        func save(_ credentials: Credentials, id: String) throws {
            guard UUID(uuidString: id) != nil else { throw StorageError.invalidData }
            _ = try URLDeliveryValidator.validate(credentials.urlString, allowingInsecureLocal: true)
            try URLDeliveryValidator.validateHeaders(credentials.customHeaders)
            if let token = credentials.bearerToken {
                guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else {
                    throw StorageError.invalidData
                }
            }
            let data = try JSONEncoder().encode(credentials)
            let update = client.update(id, data)
            let status = update == errSecItemNotFound ? client.add(id, data) : update
            guard status == errSecSuccess else { throw StorageError.unavailable(status) }
        }

        func delete(id: String) throws {
            let status = client.delete(id)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw StorageError.unavailable(status)
            }
        }
    }
}
