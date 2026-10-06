import CryptoKit
import Darwin
import Foundation

public struct URLDeliveryEvent: Equatable, Sendable {
    public enum Result: Equatable, Sendable {
        case delivered(statusCode: Int)
        case queued
        /// Existing journal state owns this identity; do not dispatch again.
        case retained
        case failed(message: String, retryable: Bool)
        case disabled
    }

    public let id: UUID
    public let transcriptID: UUID?
    public let attempts: Int
    public let result: Result

    public init(id: UUID = UUID(), transcriptID: UUID?, attempts: Int, result: Result) {
        self.id = id
        self.transcriptID = transcriptID
        self.attempts = attempts
        self.result = result
    }
}

/// Privacy-limited tombstone. No body, header values, URL path/query, or raw
/// transport errors are written here. Prepared bytes live separately until sent.
public struct URLDeliveryReceipt: Codable, Equatable, Sendable, Identifiable {
    public enum Outcome: String, Codable, Sendable {
        case pending
        case delivered
        case retryable
        case permanent
        case unknownOutcome
        case needsAuthentication
        case discarded
    }

    public let id: String
    public let urlString: String // origin only
    public let attempt: Int
    public let outcome: Outcome
    public let statusCode: Int?
    public let message: String
    public let date: Date
    public var destinationFingerprint: String? = nil
    /// Verifies an exact handoff even after the body has been removed. This is
    /// a digest of the UUID/timestamp-bearing JSON; it stores no body bytes.
    public var payloadFingerprint: String? = nil

    /// Recovery metadata, excluding URL credentials, path, query and fragment.
    /// Malformed and non-HTTP legacy endpoints have no displayable origin.
    public var origin: String? {
        guard var components = URLComponents(string: urlString), let host = components.host, !host.isEmpty,
              components.scheme == "https" || components.scheme == "http" else { return nil }
        components.user = nil
        components.password = nil
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.string
    }

    /// Offer current preset credentials without exposing endpoint paths/queries
    /// in recovery UI or authorizing a different destination.
    public func matchesDestination(_ settings: CapturePresetURLDeliverySettings) -> Bool {
        guard let destinationFingerprint,
              let url = try? URLDeliveryValidator.validate(settings.urlString, allowingInsecureLocal: settings.allowingInsecureLocal)
        else { return false }
        let fingerprint = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return fingerprint == destinationFingerprint
    }
}

/// HTTP-target JSON delivery. Never writes a note or drains on app launch.
/// A failed delivery retains immutable bytes for an explicit HTTP-only retry;
/// replaying a successful identity does not POST again. Receivers MUST implement
/// Idempotency-Key deduplication to close a server-commit/local-receipt crash gap.
public actor TranscriptURLDeliverer {
    public typealias TokenProvider = @Sendable (String) throws -> String?
    public typealias CredentialsProvider = @Sendable (String) throws -> URLDeliveryKeychain.Credentials?
    public typealias Logger = @Sendable (String) -> Void
    public typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    private struct PreparedDelivery: Codable {
        var id: String
        var transcriptID: UUID?
        var body: Data
        var bodyDigest: String
        var url: URL
        var settings: CapturePresetURLDeliverySettings
        var userAgent: String
    }

    private enum DeliveryError: LocalizedError {
        case storage
        case changedDestination
        case changedPayload
        case legacyReceipt
        case incompletePreparation
        case inProgress
        case discarded
        case canceled

        var errorDescription: String? {
            switch self {
            case .storage:
                "URL delivery could not be saved locally. Check available storage before retrying."
            case .changedDestination:
                "This delivery belongs to a different endpoint. Its destination cannot change during retry."
            case .changedPayload:
                "This capture already has different saved HTTP content. Your edited draft is preserved. Recover the original in URL Deliveries and send these edits as a new capture."
            case .legacyReceipt:
                "This legacy URL receipt cannot prove its destination or payload. Check the endpoint before resending."
            case .incompletePreparation:
                "The pending URL delivery is incomplete or corrupt. No request was made."
            case .inProgress:
                "This URL delivery is already in progress."
            case .discarded:
                "This HTTP delivery was discarded. Your draft is preserved. Send it as a new capture."
            case .canceled:
                "URL delivery was canceled. Its prepared payload is retained for an explicit retry."
            }
        }
    }

    private static let backoffBase: [TimeInterval] = [1, 4, 15, 60]
    private let session: URLSession
    private let receiptsDirectoryURL: URL
    /// Compatibility injection for package transport tests; production reads a
    /// complete destination-bound credential record, never a host-scoped token.
    private let tokenProvider: TokenProvider?
    private let credentialsProvider: CredentialsProvider
    private let logger: Logger
    private let sleeper: Sleeper
    private let removePayload: @Sendable (URL) throws -> Void

    public init(
        session: URLSession? = nil,
        receiptsDirectoryURL: URL,
        tokenProvider: TokenProvider? = nil,
        credentialsProvider: @escaping CredentialsProvider = { try URLDeliveryKeychain.credentials(forID: $0) },
        logger: @escaping Logger = { KeyboardDebugLog.shared.log("[TranscriptURLDeliverer] \($0)") },
        sleeper: @escaping Sleeper = { try await Task.sleep(for: .seconds(min(300, max(0, $0)))) },
        removePayload: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: configuration)
        }
        self.receiptsDirectoryURL = receiptsDirectoryURL
        self.tokenProvider = tokenProvider
        self.credentialsProvider = credentialsProvider
        self.logger = logger
        self.sleeper = sleeper
        self.removePayload = removePayload
    }

    public static var defaultUserAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if os(macOS)
        return "Vox.md/\(version) (macOS \(os.majorVersion).\(os.minorVersion))"
        #else
        return "Vox.md/\(version) (iOS \(os.majorVersion).\(os.minorVersion))"
        #endif
    }

    private static let defaultDeliverer = TranscriptURLDeliverer(
        receiptsDirectoryURL: AppConstants.urlDeliveryReceiptsDirectoryURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Voxboard/url-delivery-receipts", isDirectory: true)
    )

    public static func appDefault() -> TranscriptURLDeliverer { defaultDeliverer }

    @discardableResult
    public func deliver(
        transcript: Transcript,
        settings: CapturePresetURLDeliverySettings,
        userAgent: String = TranscriptURLDeliverer.defaultUserAgent
    ) async -> URLDeliveryEvent {
        guard settings.enabled else { return event(transcript.id, 0, .disabled) }
        do {
            let url = try URLDeliveryValidator.validate(settings.urlString, allowingInsecureLocal: settings.allowingInsecureLocal)
            let body = try makeBody(transcript: transcript, includeCleanedText: settings.includeCleanedText)
            return await send(body: body, url: url, settings: settings, idempotencyKey: transcript.id.uuidString.lowercased(),
                              transcriptID: transcript.id, userAgent: userAgent)
        } catch {
            return failure(transcript.id, 0, message: validationMessage(error))
        }
    }

    @discardableResult
    public func deliverCapture(
        id: UUID,
        text: String,
        date: Date,
        settings: CapturePresetURLDeliverySettings,
        userAgent: String = TranscriptURLDeliverer.defaultUserAgent
    ) async -> URLDeliveryEvent {
        guard settings.enabled else { return event(nil, 0, .disabled) }
        do {
            let url = try URLDeliveryValidator.validate(settings.urlString, allowingInsecureLocal: settings.allowingInsecureLocal)
            return await send(body: Self.captureBody(id: id, text: text, date: date), url: url, settings: settings,
                              idempotencyKey: id.uuidString.lowercased(), transcriptID: nil, userAgent: userAgent)
        } catch {
            return failure(nil, 0, message: validationMessage(error))
        }
    }

    static func captureBody(id: UUID, text: String, date: Date) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let object: [String: Any] = [
            "id": id.uuidString.lowercased(), "text": text, "source": "vox",
            "recorded_at": formatter.string(from: date),
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    /// Explicit synthetic test, with a fresh identity so a prior successful test
    /// cannot mask a changed or unreachable endpoint.
    @discardableResult
    public func sendTest(
        settings: CapturePresetURLDeliverySettings,
        userAgent: String = TranscriptURLDeliverer.defaultUserAgent
    ) async -> URLDeliveryEvent {
        guard settings.enabled else { return event(nil, 0, .disabled) }
        do {
            let url = try URLDeliveryValidator.validate(settings.urlString, allowingInsecureLocal: settings.allowingInsecureLocal)
            let id = UUID().uuidString.lowercased()
            let body = try JSONSerialization.data(withJSONObject: [
                "id": id, "text": "Vox.md delivery test", "test": true,
            ], options: [.sortedKeys])
            return await send(body: body, url: url, settings: settings, idempotencyKey: id,
                              transcriptID: nil, userAgent: userAgent)
        } catch {
            return failure(nil, 0, message: validationMessage(error))
        }
    }

    public func receipts() -> [URLDeliveryReceipt] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: receiptsDirectoryURL, includingPropertiesForKeys: nil) else {
            return []
        }
        var receipts = urls.filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasSuffix(".request.json") }
            .compactMap { try? JSONDecoder().decode(URLDeliveryReceipt.self, from: Data(contentsOf: $0)) }
        for url in urls where url.lastPathComponent.hasSuffix(".request.json") {
            let key = String(url.lastPathComponent.dropLast(".request.json".count))
            guard UUID(uuidString: key)?.uuidString.lowercased() == key else { continue }
            if let recovered = recoverIncompleteReceipt(key) { receipts.append(recovered) }
        }
        return receipts.sorted { $0.date > $1.date }
    }

    /// A process can exit between the separate body and receipt writes. Recover
    /// that body under the sender's lock, never while another process publishes
    /// it. Treat missing evidence conservatively: only explicit Retry may send.
    private func recoverIncompleteReceipt(_ key: String) -> URLDeliveryReceipt? {
        guard !FileManager.default.fileExists(atPath: receiptURL(key).path),
              let descriptor = try? acquireLock(key) else { return nil }
        defer { close(descriptor) }
        guard !FileManager.default.fileExists(atPath: receiptURL(key).path),
              FileManager.default.fileExists(atPath: requestURL(key).path) else { return nil }

        // No credential lookup or HTTP. Even a corrupt body stays discoverable
        // for Discard; absent fingerprints prevent it from being sent.
        let prepared = try? loadPrepared(key)
        var origin = URLComponents()
        origin.scheme = prepared?.url.scheme
        origin.host = prepared?.url.host
        origin.port = prepared?.url.port
        let recovered = URLDeliveryReceipt(
            id: key, urlString: origin.string ?? "", attempt: 0, outcome: .unknownOutcome,
            statusCode: nil, message: "The HTTP handoff was interrupted. Check the endpoint before retrying or discard the saved payload.",
            date: Date(), destinationFingerprint: prepared.map { Self.digest(Data($0.url.absoluteString.utf8)) },
            payloadFingerprint: prepared?.bodyDigest
        )
        // A full disk must not hide retained content from recovery. Sending or
        // discarding still requires a durable receipt and fails closed on I/O.
        try? persist(recovered, to: receiptURL(key))
        return recovered
    }

    public func pendingReceipts() -> [URLDeliveryReceipt] {
        receipts().filter {
            $0.outcome == .pending || $0.outcome == .retryable
                || $0.outcome == .unknownOutcome || $0.outcome == .needsAuthentication
        }
    }

    public func outstandingReceipts() -> [URLDeliveryReceipt] {
        receipts().filter {
            ($0.outcome != .delivered && $0.outcome != .discarded)
                || FileManager.default.fileExists(atPath: requestURL($0.id).path)
        }
    }

    /// Cleanup only: preserve the delivered anti-replay receipt, never acquire
    /// credentials or POST. A failure leaves the body visible for another try.
    public func cleanupDeliveredPayload(id: UUID) throws {
        let key = id.uuidString.lowercased()
        let descriptor = try acquireLock(key)
        defer { close(descriptor) }
        guard try loadReceipt(key)?.outcome == .delivered else { throw DeliveryError.incompletePreparation }
        if FileManager.default.fileExists(atPath: requestURL(key).path) {
            try removePayload(requestURL(key))
        }
    }

    /// Must be called by an explicit Retry action. It never reruns a note sink,
    /// reads a mutable preset, or substitutes a freshly rendered body. Manual
    /// retry grants another bounded attempt window with the same idempotency key.
    public func retryPendingDelivery(
        id: UUID, authorization: CapturePresetURLDeliverySettings? = nil
    ) async -> URLDeliveryEvent {
        if let authorization {
            do { try replaceAuthorization(id: id, using: authorization) }
            catch { return failure(nil, 0, message: validationMessage(error)) }
        }
        return await sendStoredDelivery(id: id, explicitRetry: true)
    }

    /// A deliberate recovery action may replace credential references, never
    /// the frozen endpoint, content or identity. This also recovers an original
    /// anonymous 401 or a replaced/missing Keychain account without retargeting.
    private func replaceAuthorization(id: UUID, using authorization: CapturePresetURLDeliverySettings) throws {
        try Task.checkCancellation()
        let key = id.uuidString.lowercased()
        let descriptor = try acquireLock(key)
        defer { close(descriptor) }
        let prepared = try loadPrepared(key)
        let receipt = try loadReceipt(key)
        guard receipt?.outcome != .delivered, receipt?.outcome != .discarded else { throw DeliveryError.incompletePreparation }
        let endpoint = try URLDeliveryValidator.validate(authorization.urlString, allowingInsecureLocal: authorization.allowingInsecureLocal)
        guard endpoint == prepared.url else { throw DeliveryError.changedDestination }
        guard authorization.customHeaders.isEmpty, !authorization.requiresCredentialMigration else {
            throw URLDeliveryKeychain.StorageError.missingCredentials
        }
        var settings = prepared.settings
        settings.credentialID = authorization.credentialID
        settings.credentialURLString = authorization.credentialURLString
        settings.hasBearerToken = authorization.hasBearerToken
        settings.hasCustomHeaders = authorization.hasCustomHeaders
        settings.customHeaders = [:]
        settings.requiresCredentialMigration = false
        let replacement = PreparedDelivery(id: prepared.id, transcriptID: prepared.transcriptID,
            body: prepared.body, bodyDigest: prepared.bodyDigest, url: prepared.url, settings: settings, userAgent: prepared.userAgent)
        // Fail closed and leave the journal unchanged if the chosen account is
        // missing, locked, or bound to another endpoint.
        _ = try makeRequest(replacement)
        try persist(replacement, to: requestURL(key))
    }

    /// Commits an HTTP-only handoff without accessing credentials or contacting
    /// the endpoint. Hosts await this before completing their local capture.
    /// Editable composers must require a matching payload before clearing a
    /// draft; recording retries may retain an earlier immutable handoff.
    public func enqueueCapture(
        id: UUID, text: String, date: Date, settings: CapturePresetURLDeliverySettings,
        userAgent: String = TranscriptURLDeliverer.defaultUserAgent,
        requireMatchingPayload: Bool = false
    ) -> URLDeliveryEvent {
        guard settings.enabled else { return event(nil, 0, .disabled) }
        let body = Self.captureBody(id: id, text: text, date: date)
        return enqueue(body: body, id: id, transcriptID: nil, settings: settings, userAgent: userAgent,
                       expectedBodyDigest: requireMatchingPayload ? Self.digest(body) : nil)
    }

    public func enqueueTranscript(
        _ transcript: Transcript, settings: CapturePresetURLDeliverySettings,
        userAgent: String = TranscriptURLDeliverer.defaultUserAgent
    ) -> URLDeliveryEvent {
        guard settings.enabled else { return event(transcript.id, 0, .disabled) }
        do {
            return enqueue(body: try makeBody(transcript: transcript, includeCleanedText: settings.includeCleanedText),
                           id: transcript.id, transcriptID: transcript.id, settings: settings, userAgent: userAgent)
        } catch {
            return failure(transcript.id, 0, message: validationMessage(error))
        }
    }

    /// Dispatches only an unattempted, already durable handoff. Relaunch does
    /// not automatically replay a failed or ambiguous POST.
    public func sendQueuedDelivery(id: UUID) async -> URLDeliveryEvent {
        await sendStoredDelivery(id: id, explicitRetry: false)
    }

    /// Retains a content-free tombstone so discarded identities cannot be
    /// silently resubmitted by another sink's retry. An active sender holds the
    /// same lock; its task owner must cancel and await it before discarding.
    public func discardDelivery(id: UUID) throws {
        let key = id.uuidString.lowercased()
        let descriptor = try acquireLock(key)
        defer { close(descriptor) }
        guard let previous = try loadReceipt(key) else { throw DeliveryError.incompletePreparation }
        var origin = URLComponents(string: previous.urlString)
        origin?.user = nil
        origin?.password = nil
        origin?.path = ""
        origin?.query = nil
        origin?.fragment = nil
        let discarded = URLDeliveryReceipt(id: key, urlString: origin?.string ?? "", attempt: previous.attempt,
            outcome: .discarded, statusCode: previous.statusCode, message: "Discarded locally", date: Date(),
            destinationFingerprint: previous.destinationFingerprint, payloadFingerprint: previous.payloadFingerprint)
        try persist(discarded, to: receiptURL(key))
        if FileManager.default.fileExists(atPath: requestURL(key).path) {
            try removePayload(requestURL(key))
        }
    }

    private func enqueue(
        body: Data, id: UUID, transcriptID: UUID?, settings: CapturePresetURLDeliverySettings, userAgent: String,
        expectedBodyDigest: String? = nil
    ) -> URLDeliveryEvent {
        let key = id.uuidString.lowercased()
        do {
            try Task.checkCancellation()
            let url = try URLDeliveryValidator.validate(settings.urlString, allowingInsecureLocal: settings.allowingInsecureLocal)
            try URLDeliveryValidator.validateBody(body)
            try URLDeliveryValidator.validateHeaders(["User-Agent": userAgent])
            // In-memory secrets cannot become a durable handoff. The settings
            // editor must first save all header values in a Keychain account.
            guard settings.customHeaders.isEmpty else { throw URLDeliveryKeychain.StorageError.missingCredentials }
            let descriptor: Int32
            do { descriptor = try acquireLock(key) }
            catch DeliveryError.inProgress {
                // A sender already owns a durable handoff. Do not make a local
                // sink retry wait for HTTP, mutate its journal, or dispatch it.
                return try retainedBusyHandoff(key: key, url: url, transcriptID: transcriptID, expectedBodyDigest: expectedBodyDigest)
            }
            defer { close(descriptor) }
            if let previous = try loadReceipt(key) {
                guard let fingerprint = previous.destinationFingerprint else { throw DeliveryError.legacyReceipt }
                guard fingerprint == Self.digest(Data(url.absoluteString.utf8)) else { throw DeliveryError.changedDestination }
                try requireMatchingPayload(expectedBodyDigest, receipt: previous)
                if previous.outcome == .delivered {
                    return event(transcriptID, previous.attempt, .delivered(statusCode: previous.statusCode ?? 200))
                }
                if previous.outcome == .discarded { return event(transcriptID, previous.attempt, .retained) }
                if previous.outcome != .pending || previous.attempt != 0 {
                    let prepared = try loadPrepared(key)
                    guard prepared.url == url else { throw DeliveryError.changedDestination }
                    return event(transcriptID, previous.attempt, .retained)
                }
            }
            let prepared: PreparedDelivery
            if FileManager.default.fileExists(atPath: requestURL(key).path) {
                prepared = try loadPrepared(key)
                guard prepared.url == url else { throw DeliveryError.changedDestination }
                if let expectedBodyDigest, prepared.bodyDigest != expectedBodyDigest { throw DeliveryError.changedPayload }
            } else {
                prepared = PreparedDelivery(id: key, transcriptID: transcriptID, body: body,
                    bodyDigest: Self.digest(body), url: url, settings: settings, userAgent: userAgent)
            }
            try persist(prepared, to: requestURL(key))
            try record(id: key, url: url, attempt: 0, outcome: .pending, message: "Saved locally; awaiting URL delivery",
                       payloadFingerprint: prepared.bodyDigest)
            return event(transcriptID, 0, .queued)
        } catch {
            return failure(transcriptID, 0, message: Task.isCancelled ? DeliveryError.canceled.localizedDescription : validationMessage(error))
        }
    }

    private func requireMatchingPayload(_ expectedDigest: String?, receipt: URLDeliveryReceipt) throws {
        guard let expectedDigest else { return }
        // A tombstone suppresses recording replays, but cannot acknowledge an
        // editable draft whose saved payload was deliberately removed.
        guard receipt.outcome != .discarded else { throw DeliveryError.discarded }
        // Legacy pending records can prove their payload from the retained body.
        // A body-free legacy tombstone cannot prove an edited draft was accepted.
        let actualDigest: String
        if let fingerprint = receipt.payloadFingerprint {
            actualDigest = fingerprint
        } else {
            actualDigest = try loadPrepared(receipt.id).bodyDigest
        }
        guard actualDigest == expectedDigest else { throw DeliveryError.changedPayload }
    }

    private func retainedBusyHandoff(
        key: String, url: URL, transcriptID: UUID?, expectedBodyDigest: String?
    ) throws -> URLDeliveryEvent {
        func checkedReceipt() throws -> URLDeliveryReceipt {
            guard let receipt = try loadReceipt(key), receipt.id == key else { throw DeliveryError.incompletePreparation }
            guard let fingerprint = receipt.destinationFingerprint else { throw DeliveryError.legacyReceipt }
            guard fingerprint == Self.digest(Data(url.absoluteString.utf8)) else { throw DeliveryError.changedDestination }
            try requireMatchingPayload(expectedBodyDigest, receipt: receipt)
            return receipt
        }
        let receipt = try checkedReceipt()
        if receipt.outcome == .delivered {
            return event(transcriptID, receipt.attempt, .delivered(statusCode: receipt.statusCode ?? 200))
        }
        if receipt.outcome == .discarded { return event(transcriptID, receipt.attempt, .retained) }
        do {
            let prepared = try loadPrepared(key)
            guard prepared.url == url else { throw DeliveryError.changedDestination }
        } catch {
            // A different process may have finished/discarded between reads.
            // Only a verified terminal tombstone justifies a missing body.
            let latest = try checkedReceipt()
            if latest.outcome == .delivered {
                return event(transcriptID, latest.attempt, .delivered(statusCode: latest.statusCode ?? 200))
            }
            if latest.outcome != .discarded { throw error }
        }
        return event(transcriptID, receipt.attempt, .retained)
    }

    private func sendStoredDelivery(id: UUID, explicitRetry: Bool) async -> URLDeliveryEvent {
        let key = id.uuidString.lowercased()
        do {
            try Task.checkCancellation()
            if let receipt = try loadReceipt(key), receipt.outcome == .delivered {
                guard receipt.destinationFingerprint != nil else { throw DeliveryError.legacyReceipt }
                return event(nil, receipt.attempt, .delivered(statusCode: receipt.statusCode ?? 200))
            }
            let prepared = try loadPrepared(key)
            return await send(body: prepared.body, url: prepared.url, settings: prepared.settings,
                              idempotencyKey: key, transcriptID: prepared.transcriptID,
                              userAgent: prepared.userAgent, explicitRetry: explicitRetry, dispatchQueued: !explicitRetry)
        } catch {
            return failure(nil, 0, message: Task.isCancelled ? DeliveryError.canceled.localizedDescription : validationMessage(error))
        }
    }

    // MARK: - Sending and write-ahead state

    private func send(
        body: Data, url: URL, settings: CapturePresetURLDeliverySettings,
        idempotencyKey: String, transcriptID: UUID?, userAgent: String,
        explicitRetry: Bool = false, dispatchQueued: Bool = false
    ) async -> URLDeliveryEvent {
        var attempts = 0
        do {
            try Task.checkCancellation()
            try URLDeliveryValidator.validateBody(body)
            let descriptor = try acquireLock(idempotencyKey)
            defer { close(descriptor) }

            let fingerprint = Self.digest(Data(url.absoluteString.utf8))
            let previous = try loadReceipt(idempotencyKey)
            if let previous {
                attempts = previous.attempt
                guard let priorDestination = previous.destinationFingerprint else { throw DeliveryError.legacyReceipt }
                guard priorDestination == fingerprint else { throw DeliveryError.changedDestination }
                if previous.outcome == .delivered {
                    return event(transcriptID, previous.attempt, .delivered(statusCode: previous.statusCode ?? 200))
                }
                let unattemptedHandoff = dispatchQueued && previous.outcome == .pending && previous.attempt == 0
                // A deliberate Retry may recover even a permanent rejection,
                // but a discarded identity and automatic replays never POST.
                if previous.outcome == .discarded || (!explicitRetry && !unattemptedHandoff) {
                    return failure(transcriptID, previous.attempt, message: previous.message,
                                   retryable: previous.outcome != .discarded)
                }
            }

            let prepared: PreparedDelivery
            if FileManager.default.fileExists(atPath: requestURL(idempotencyKey).path) {
                prepared = try loadPrepared(idempotencyKey)
                guard prepared.url == url else { throw DeliveryError.changedDestination }
            } else {
                guard !explicitRetry else { throw DeliveryError.incompletePreparation }
                prepared = PreparedDelivery(id: idempotencyKey, transcriptID: transcriptID, body: body,
                                            bodyDigest: Self.digest(body), url: url, settings: settings, userAgent: userAgent)
            }
            let request = try makeRequest(prepared)
            try persist(prepared, to: requestURL(idempotencyKey))
            // Preserve prior attempts and ambiguity through retry preparation.
            // Cancellation or process exit before the next POST must not turn
            // previously attempted work into an automatic, unattempted send.
            if previous == nil {
                try record(id: idempotencyKey, url: url, attempt: 0, outcome: .pending, message: "Awaiting URL delivery",
                           payloadFingerprint: prepared.bodyDigest)
            }

            let maxAttempts = min(5, max(1, prepared.settings.maxAttempts))
            logger("begin id=\(idempotencyKey) bytes=\(prepared.body.count)")
            for attempt in 1...maxAttempts {
                try Task.checkCancellation()
                // Removal/replacement during backoff must not reuse a token
                // already copied into URLRequest. Do not silently switch auth.
                let refreshed = try makeRequest(prepared)
                guard refreshed.allHTTPHeaderFields == request.allHTTPHeaderFields else {
                    throw URLDeliveryKeychain.StorageError.missingCredentials
                }
                // If the process dies after the POST, automatic replay cannot
                // claim it failed or succeeded. Only explicit retry may proceed.
                try record(id: idempotencyKey, url: url, attempt: attempt, outcome: .unknownOutcome,
                           message: "The endpoint may have received this delivery. Check it before retrying.")
                attempts = attempt
                let response: URLResponse
                do {
                    // We need only the status, not an unbounded response body.
                    let (bytes, received) = try await session.bytes(for: request, delegate: URLDeliveryRedirectBlocker())
                    bytes.task.cancel()
                    response = received
                } catch {
                    if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                        try record(id: idempotencyKey, url: url, attempt: attempt, outcome: .retryable,
                                   message: DeliveryError.canceled.localizedDescription)
                        return failure(transcriptID, attempt, message: DeliveryError.canceled.localizedDescription, retryable: true)
                    }
                    let retryable = Self.isRetryable(error: error)
                    let message = "URL delivery failed with a transport error."
                    try record(id: idempotencyKey, url: url, attempt: attempt,
                               outcome: retryable ? .retryable : .permanent, message: message)
                    logger("attempt=\(attempt) id=\(idempotencyKey) transport-error")
                    guard retryable, attempt < maxAttempts else {
                        return failure(transcriptID, attempt, message: message, retryable: retryable)
                    }
                    try await sleeper(Self.backoff(forFailedAttempt: attempt))
                    continue
                }

                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(status) {
                    try record(id: idempotencyKey, url: url, attempt: attempt, outcome: .delivered,
                               statusCode: status, message: "Delivered")
                    // Remote delivery succeeded even if local cleanup fails.
                    // Recovery exposes the retained body as cleanup-only work.
                    try? removePayload(requestURL(idempotencyKey))
                    logger("delivered id=\(idempotencyKey) status=\(status) attempt=\(attempt)")
                    return event(transcriptID, attempt, .delivered(statusCode: status))
                }
                let retryable = Self.isRetryable(statusCode: status)
                let message = (300..<400).contains(status)
                    ? "URL redirects are not followed. Configure the endpoint's final URL."
                    : "The endpoint returned HTTP \(status)."
                let outcome: URLDeliveryReceipt.Outcome = status == 401 || status == 403
                    ? .needsAuthentication : (retryable ? .retryable : .permanent)
                try record(id: idempotencyKey, url: url, attempt: attempt,
                           outcome: outcome, statusCode: status, message: message)
                logger("attempt=\(attempt) id=\(idempotencyKey) status=\(status)")
                guard retryable, attempt < maxAttempts else {
                    return failure(transcriptID, attempt, message: message, retryable: retryable)
                }
                try await sleeper(Self.retryAfter(from: response) ?? Self.backoff(forFailedAttempt: attempt))
            }
        } catch {
            if Task.isCancelled || error is CancellationError {
                return failure(transcriptID, attempts, message: DeliveryError.canceled.localizedDescription, retryable: true)
            }
            if error is URLDeliveryKeychain.StorageError,
               FileManager.default.fileExists(atPath: requestURL(idempotencyKey).path) {
                try? record(id: idempotencyKey, url: url, attempt: attempts, outcome: .needsAuthentication,
                            message: validationMessage(error))
            }
            // Never echo Foundation / provider error descriptions: they can
            // contain private URL paths, query values, or credentials.
            return failure(transcriptID, attempts, message: attempts > 0
                           && !(error is URLDeliveryValidationError) && !(error is URLDeliveryKeychain.StorageError)
                           ? "The endpoint may have received this delivery, but its receipt could not be saved. Check it before retrying."
                           : validationMessage(error))
        }
        return failure(transcriptID, attempts, message: "URL delivery did not complete.")
    }

    private func makeRequest(_ prepared: PreparedDelivery) throws -> URLRequest {
        let settings = prepared.settings
        guard !settings.requiresCredentialMigration else { throw URLDeliveryKeychain.StorageError.missingCredentials }
        var token: String?
        var headers = settings.customHeaders
        if let id = settings.credentialID, settings.hasBearerToken || settings.hasCustomHeaders {
            guard settings.credentialURLString == prepared.url.absoluteString,
                  let credentials = try credentialsProvider(id), credentials.urlString == prepared.url.absoluteString else {
                throw URLDeliveryKeychain.StorageError.destinationChanged
            }
            token = credentials.bearerToken
            headers = settings.hasCustomHeaders ? credentials.customHeaders : [:]
        } else {
            if settings.hasBearerToken { token = try tokenProvider?(settings.credentialID ?? "") }
        }
        if settings.hasCustomHeaders, headers.isEmpty { throw URLDeliveryKeychain.StorageError.missingCredentials }
        if settings.hasBearerToken {
            guard let token, !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else {
                throw URLDeliveryKeychain.StorageError.missingCredentials
            }
        }
        try URLDeliveryValidator.validateHeaders(headers)
        try URLDeliveryValidator.validateHeaders(["User-Agent": prepared.userAgent])
        var request = URLRequest(url: prepared.url)
        request.httpMethod = "POST"
        request.httpBody = prepared.body
        request.timeoutInterval = 30
        request.setValue(prepared.userAgent, forHTTPHeaderField: "User-Agent")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(prepared.id, forHTTPHeaderField: "Idempotency-Key")
        if settings.hasBearerToken, let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func makeBody(transcript: Transcript, includeCleanedText: Bool) throws -> Data {
        let configuration = TranscriptExportConfiguration(
            format: .json, mode: .newFile,
            enrichmentOptions: TranscriptExportEnrichmentOptions(
                useEnrichedTitleInFilename: false, useCleanedText: includeCleanedText, includeTags: true
            )
        )
        let rendered = try TranscriptFileExporter.exportKitRenderedContent(transcript, configuration: configuration)
        guard !includeCleanedText, transcript.cleanedText != nil,
              var object = try JSONSerialization.jsonObject(with: Data(rendered.utf8)) as? [String: Any] else {
            return Data(rendered.utf8)
        }
        object.removeValue(forKey: "cleanedText")
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// The descriptor owns flock until close, including across actor awaits.
    private func acquireLock(_ id: String) throws -> Int32 {
        try FileManager.default.createDirectory(at: receiptsDirectoryURL, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let descriptor = open(receiptsDirectoryURL.appendingPathComponent("\(id).lock").path,
                              O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw DeliveryError.storage }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw DeliveryError.inProgress
        }
        return descriptor
    }

    private func receiptURL(_ id: String) -> URL { receiptsDirectoryURL.appendingPathComponent("\(id).json") }
    private func requestURL(_ id: String) -> URL { receiptsDirectoryURL.appendingPathComponent("\(id).request.json") }

    private func loadReceipt(_ id: String) throws -> URLDeliveryReceipt? {
        guard FileManager.default.fileExists(atPath: receiptURL(id).path) else { return nil }
        let receipt = try JSONDecoder().decode(URLDeliveryReceipt.self, from: Data(contentsOf: receiptURL(id)))
        guard receipt.id == id,
              receipt.outcome != .delivered || receipt.statusCode.map({ (200..<300).contains($0) }) == true else {
            throw DeliveryError.incompletePreparation
        }
        return receipt
    }

    private func loadPrepared(_ id: String) throws -> PreparedDelivery {
        let prepared = try JSONDecoder().decode(PreparedDelivery.self, from: Data(contentsOf: requestURL(id)))
        guard prepared.id == id, prepared.settings.enabled,
              Self.digest(prepared.body) == prepared.bodyDigest else {
            throw DeliveryError.incompletePreparation
        }
        try URLDeliveryValidator.validateBody(prepared.body)
        let validated = try URLDeliveryValidator.validate(prepared.settings.urlString, allowingInsecureLocal: prepared.settings.allowingInsecureLocal)
        guard validated == prepared.url else { throw DeliveryError.incompletePreparation }
        return prepared
    }

    private func record(id: String, url: URL, attempt: Int, outcome: URLDeliveryReceipt.Outcome,
                        statusCode: Int? = nil, message: String, payloadFingerprint: String? = nil) throws {
        var origin = URLComponents()
        origin.scheme = url.scheme
        origin.host = url.host
        origin.port = url.port
        let receipt = URLDeliveryReceipt(id: id, urlString: origin.string ?? "", attempt: attempt, outcome: outcome,
                                         statusCode: statusCode, message: message, date: Date(),
                                         destinationFingerprint: Self.digest(Data(url.absoluteString.utf8)),
                                         payloadFingerprint: try payloadFingerprint ?? loadReceipt(id)?.payloadFingerprint)
        try persist(receipt, to: receiptURL(id))
    }

    private func persist<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func event(_ id: UUID?, _ attempts: Int, _ result: URLDeliveryEvent.Result) -> URLDeliveryEvent {
        URLDeliveryEvent(transcriptID: id, attempts: attempts, result: result)
    }

    private func failure(_ id: UUID?, _ attempts: Int, message: String, retryable: Bool = false) -> URLDeliveryEvent {
        event(id, attempts, .failed(message: message, retryable: retryable))
    }

    private func validationMessage(_ error: Error) -> String {
        if let error = error as? URLDeliveryValidationError { return error.localizedDescription }
        if let error = error as? URLDeliveryKeychain.StorageError { return error.localizedDescription }
        if let error = error as? DeliveryError { return error.localizedDescription }
        return DeliveryError.storage.localizedDescription
    }

    static func isRetryable(statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
    }

    private static func isRetryable(error: Error) -> Bool {
        guard let error = error as? URLError else { return true }
        return [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable].contains(error.code)
    }

    static func backoff(forFailedAttempt attempt: Int) -> TimeInterval {
        let base = backoffBase[min(max(0, attempt - 1), backoffBase.count - 1)]
        return base + base * Double.random(in: 0...0.25)
    }

    static func retryAfter(from response: URLResponse?) -> TimeInterval? {
        guard let http = response as? HTTPURLResponse,
              let raw = http.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces)),
              seconds.isFinite, seconds >= 0 else { return nil }
        return min(seconds, 300)
    }
}

/// Deny ALL redirects, including same-origin POST-to-GET rewrites. A redirect
/// must never receive the bearer token, custom authentication, or transcript.
final class URLDeliveryRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public extension CaptureRequest {
    var urlDeliveryText: String {
        payloads.compactMap { payload -> String? in
            switch payload {
            case .text(let text): return text
            case .url(let url, let title): return title.map { "\($0) \(url.absoluteString)" } ?? url.absoluteString
            case .audio(_, let transcript): return transcript
            case .scannedDocument(_, _, let extractedText): return extractedText
            default: return nil
            }
        }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }
}
