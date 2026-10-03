import Foundation
import Security

/// Keychain storage for per-destination bearer tokens.
///
/// Settings only ever persist `hasBearerToken`; the secret lives here, keyed by
/// the destination host, and is never logged.
public enum URLDeliveryKeychain {
    public static let service = "bontecou.Voxboard.urldelivery"

    public static func token(forHost host: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func setToken(_ token: String?, forHost host: String) -> Bool {
        guard let token, !token.isEmpty else { return deleteToken(forHost: host) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return updateStatus == errSecSuccess
    }

    @discardableResult
    public static func deleteToken(forHost host: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
