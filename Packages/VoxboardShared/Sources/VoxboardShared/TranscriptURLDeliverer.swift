import Foundation

/// The outcome of one configured URL delivery, surfaced to the recorder the
/// same way `FileExportEvent` surfaces a file export.
public struct URLDeliveryEvent: Equatable, Sendable {
    public enum Result: Equatable, Sendable {
        case delivered(statusCode: Int)
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

/// A durable record of one delivery attempt. Written next to the app's other
/// delivery artifacts so a failure survives an app restart.
public struct URLDeliveryReceipt: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case delivered
        case retryable
        case permanent
    }

    public let id: String
    public let urlString: String
    public let attempt: Int
    public let outcome: Outcome
    public let statusCode: Int?
    public let message: String
    public let date: Date
}

/// Sends a finished transcript as JSON to a user-configured endpoint.
///
/// Independent of the file sink: a preset may use URL delivery with no folder,
/// a folder with no URL, or both. Retries with exponential backoff; `4xx` is
/// permanent except `408`/`429`; `5xx`, timeouts and transport errors retry.
/// The bearer token is read through `tokenProvider` and is never logged.
public actor TranscriptURLDeliverer {
    /// Resolves the bearer token for a destination host, or nil.
    public typealias TokenProvider = @Sendable (String) -> String?
    /// A diagnostic sink. Never receives the token or the transcript body.
    public typealias Logger = @Sendable (String) -> Void
    /// Injected so tests can observe backoff without waiting.
    public typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    private static let backoffBase: [TimeInterval] = [1, 4, 15, 60]

    private let session: URLSession
    private let receiptsDirectoryURL: URL
    private let tokenProvider: TokenProvider
    private let logger: Logger
    private let sleeper: Sleeper

    public init(
        session: URLSession = .shared,
        receiptsDirectoryURL: URL,
        tokenProvider: @escaping TokenProvider = { URLDeliveryKeychain.token(forHost: $0) },
        logger: @escaping Logger = { KeyboardDebugLog.shared.log("[TranscriptURLDeliverer] \($0)") },
        sleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1_000_000_000)) }
    ) {
        self.session = session
        self.receiptsDirectoryURL = receiptsDirectoryURL
        self.tokenProvider = tokenProvider
        self.logger = logger
        self.sleeper = sleeper
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

    /// A deliverer wired to the app's App Group receipts directory. Falls back
    /// to a temporary directory when the shared container is unavailable.
    public static func appDefault() -> TranscriptURLDeliverer {
        let directory = AppConstants.urlDeliveryReceiptsDirectoryURL
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("url-delivery-receipts", isDirectory: true)
        return TranscriptURLDeliverer(receiptsDirectoryURL: directory)
    }

    /// Delivers one transcript. Returns `.disabled` immediately when the preset
    /// has not opted in; an invalid destination returns a permanent failure.
    @discardableResult
    public func deliver(
        transcript: Transcript,
        settings: CapturePresetURLDeliverySettings,
        userAgent: String = TranscriptURLDeliverer.defaultUserAgent
    ) async -> URLDeliveryEvent {
        guard settings.enabled else {
            return URLDeliveryEvent(transcriptID: transcript.id, attempts: 0, result: .disabled)
        }
        let url: URL
        do {
            url = try URLDeliveryValidator.validate(settings.urlString, allowingInsecureLocal: true)
        } catch {
            logger("invalid destination: \(error.localizedDescription)")
            return URLDeliveryEvent(
                transcriptID: transcript.id,
                attempts: 0,
                result: .failed(message: error.localizedDescription, retryable: false)
            )
        }
        let body: Data
        do {
            body = try makeBody(transcript: transcript, includeCleanedText: settings.includeCleanedText)
        } catch {
            return URLDeliveryEvent(
                transcriptID: transcript.id,
                attempts: 0,
                result: .failed(message: error.localizedDescription, retryable: false)
            )
        }
        return await send(
            body: body,
            url: url,
            settings: settings,
            idempotencyKey: transcript.id.uuidString.lowercased(),
            transcriptID: transcript.id,
            userAgent: userAgent
        )
    }

    /// Delivers a non-voice Capture (typed text, link, scan text) as a minimal
    /// JSON body. Uses the same retry, receipt, header and Keychain machinery as
    /// `deliver`. `id` is the capture request UUID, so retries are idempotent.
    @discardableResult
    public func deliverCapture(
        id: UUID,
        text: String,
        date: Date,
        settings: CapturePresetURLDeliverySettings,
        userAgent: String = TranscriptURLDeliverer.defaultUserAgent
    ) async -> URLDeliveryEvent {
        guard settings.enabled else {
            return URLDeliveryEvent(transcriptID: nil, attempts: 0, result: .disabled)
        }
        let url: URL
        do {
            url = try URLDeliveryValidator.validate(settings.urlString, allowingInsecureLocal: true)
        } catch {
            logger("invalid destination: \(error.localizedDescription)")
            return URLDeliveryEvent(
                transcriptID: nil,
                attempts: 0,
                result: .failed(message: error.localizedDescription, retryable: false)
            )
        }
        let body = Self.captureBody(id: id, text: text, date: date)
        return await send(
            body: body,
            url: url,
            settings: settings,
            idempotencyKey: id.uuidString.lowercased(),
            transcriptID: nil,
            userAgent: userAgent
        )
    }

    /// The receiver's generic shape: `text` is required, identity is `id`, and
    /// `recorded_at` is ISO-8601. Unknown extra keys are ignored server-side.
    static func captureBody(id: UUID, text: String, date: Date) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let object: [String: Any] = [
            "id": id.uuidString.lowercased(),
            "text": text,
            "source": "vox",
            "recorded_at": formatter.string(from: date),
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    /// A deliberate, user-initiated test POST with a fixed synthetic payload.
    @discardableResult
    public func sendTest(        settings: CapturePresetURLDeliverySettings,
        userAgent: String = TranscriptURLDeliverer.defaultUserAgent
    ) async -> URLDeliveryEvent {
        let url: URL
        do {
            url = try URLDeliveryValidator.validate(settings.urlString, allowingInsecureLocal: true)
        } catch {
            return URLDeliveryEvent(
                transcriptID: nil,
                attempts: 0,
                result: .failed(message: error.localizedDescription, retryable: false)
            )
        }
        let body = Data(#"{"id":"voxboard-test","text":"Vox.md delivery test","test":true}"#.utf8)
        return await send(
            body: body,
            url: url,
            settings: settings,
            idempotencyKey: "voxboard-test",
            transcriptID: nil,
            userAgent: userAgent
        )
    }

    /// Receipts still awaiting a successful delivery, newest first. Phase 2
    /// background retry can drain these; today they are retained for inspection.
    public func pendingReceipts() -> [URLDeliveryReceipt] {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: receiptsDirectoryURL,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> URLDeliveryReceipt? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(URLDeliveryReceipt.self, from: data)
            }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Sending

    private func send(
        body: Data,
        url: URL,
        settings: CapturePresetURLDeliverySettings,
        idempotencyKey: String,
        transcriptID: UUID?,
        userAgent: String
    ) async -> URLDeliveryEvent {
        do {
            try URLDeliveryValidator.validateBody(body)
        } catch {
            logger("refusing oversized body")
            return URLDeliveryEvent(
                transcriptID: transcriptID,
                attempts: 0,
                result: .failed(message: error.localizedDescription, retryable: false)
            )
        }

        let host = url.host ?? ""
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // Custom headers (e.g. an HMAC signature) are applied next. Header names
        // and values are never logged.
        for (name, value) in settings.customHeaders {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }
            request.setValue(value, forHTTPHeaderField: trimmedName)
        }
        // Protocol-critical headers are enforced after any custom ones, so a
        // preset cannot break the wire contract or strip the bearer token.
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        if settings.hasBearerToken, let token = tokenProvider(host), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let maxAttempts = max(1, settings.maxAttempts)
        // Names only, never values: safe to log and enough to prove which
        // headers the app built. `Authorization` is present iff a token was sent.
        let headerNames = (request.allHTTPHeaderFields ?? [:]).keys.sorted().joined(separator: ",")
        logger("begin id=\(idempotencyKey) host=\(host) bytes=\(body.count) headers=[\(headerNames)]")
        var attempt = 1
        while true {
            do {
                let (_, response) = try await session.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(statusCode) {
                    record(URLDeliveryReceipt(
                        id: idempotencyKey,
                        urlString: url.absoluteString,
                        attempt: attempt,
                        outcome: .delivered,
                        statusCode: statusCode,
                        message: "Delivered",
                        date: Date()
                    ))
                    logger("delivered id=\(idempotencyKey) host=\(host) status=\(statusCode) attempt=\(attempt)")
                    return URLDeliveryEvent(
                        transcriptID: transcriptID,
                        attempts: attempt,
                        result: .delivered(statusCode: statusCode)
                    )
                }

                let retryable = Self.isRetryable(statusCode: statusCode)
                record(URLDeliveryReceipt(
                    id: idempotencyKey,
                    urlString: url.absoluteString,
                    attempt: attempt,
                    outcome: retryable ? .retryable : .permanent,
                    statusCode: statusCode,
                    message: "HTTP \(statusCode)",
                    date: Date()
                ))
                logger("attempt=\(attempt) id=\(idempotencyKey) host=\(host) status=\(statusCode) retryable=\(retryable)")

                guard retryable, attempt < maxAttempts else {
                    return URLDeliveryEvent(
                        transcriptID: transcriptID,
                        attempts: attempt,
                        result: .failed(
                            message: "The endpoint returned HTTP \(statusCode).",
                            retryable: retryable
                        )
                    )
                }
                let delay = Self.retryAfter(from: response) ?? Self.backoff(forFailedAttempt: attempt)
                try? await sleeper(delay)
                attempt += 1
            } catch {
                record(URLDeliveryReceipt(
                    id: idempotencyKey,
                    urlString: url.absoluteString,
                    attempt: attempt,
                    outcome: .retryable,
                    statusCode: nil,
                    message: error.localizedDescription,
                    date: Date()
                ))
                logger("attempt=\(attempt) id=\(idempotencyKey) host=\(host) transport-error=\(error.localizedDescription)")
                guard attempt < maxAttempts else {
                    return URLDeliveryEvent(
                        transcriptID: transcriptID,
                        attempts: attempt,
                        result: .failed(message: error.localizedDescription, retryable: true)
                    )
                }
                try? await sleeper(Self.backoff(forFailedAttempt: attempt))
                attempt += 1
            }
        }
    }

    private func makeBody(transcript: Transcript, includeCleanedText: Bool) throws -> Data {
        let configuration = TranscriptExportConfiguration(
            format: .json,
            mode: .newFile,
            enrichmentOptions: TranscriptExportEnrichmentOptions(
                useEnrichedTitleInFilename: false,
                useCleanedText: includeCleanedText,
                includeTags: true
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

    private func record(_ receipt: URLDeliveryReceipt) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: receiptsDirectoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(receipt) else { return }
        try? data.write(
            to: receiptsDirectoryURL.appendingPathComponent("\(receipt.id).json", isDirectory: false),
            options: .atomic
        )
    }

    static func isRetryable(statusCode: Int) -> Bool {
        if statusCode == 408 || statusCode == 429 { return true }
        return (500...599).contains(statusCode)
    }

    static func backoff(forFailedAttempt attempt: Int) -> TimeInterval {
        let index = min(max(0, attempt - 1), backoffBase.count - 1)
        let base = backoffBase[index]
        return base + base * Double.random(in: 0...0.25)
    }

    /// Seconds only; HTTP-date `Retry-After` falls back to computed backoff.
    static func retryAfter(from response: URLResponse?) -> TimeInterval? {
        guard let http = response as? HTTPURLResponse,
              let raw = http.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces)),
              seconds >= 0 else { return nil }
        return min(seconds, 300)
    }
}

public extension CaptureRequest {
    /// Plain-text projection for URL delivery: typed text, link, transcript, or
    /// scan text, joined in payload order. Empty when the capture has no text
    /// (for example an image-only capture).
    var urlDeliveryText: String {
        payloads
            .compactMap { payload -> String? in
                switch payload {
                case .text(let text):
                    return text
                case .url(let url, let title):
                    return title.map { "\($0) \(url.absoluteString)" } ?? url.absoluteString
                case .audio(_, let transcript):
                    return transcript
                case .scannedDocument(_, _, let extractedText):
                    return extractedText
                default:
                    return nil
                }
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
