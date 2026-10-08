import Foundation
@testable import VoxboardShared

/// Synthetic Keychain boundary used to model removal during an HTTP backoff.
final class URLDeliveryCredentialBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: URLDeliveryKeychain.Credentials?

    init(_ credentials: URLDeliveryKeychain.Credentials) { storage = credentials }

    var value: URLDeliveryKeychain.Credentials? {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func remove() {
        lock.lock(); defer { lock.unlock() }
        storage = nil
    }
}
