import Foundation

/// One status-only step of a capture's trip through its route. Steps carry no
/// captured words, links or locations, so they are safe to show in Activity.
public struct CaptureRouteLogStep: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// The capture was taken (typed, spoken, shared, imported).
        case capture
        /// The route's on-device processing (cleanup, summaries, image text).
        case process
        /// Rendering the entry with the route's template.
        case shape
        /// Writing the entry into the vault note.
        case deliver
    }

    public enum Outcome: String, Codable, Sendable {
        case succeeded
        case failed
        case skipped
    }

    public var kind: Kind
    public var outcome: Outcome
    public var at: Date?
    /// Short status text such as a destination path or failure category.
    public var detail: String?

    public var id: Kind { kind }

    public init(kind: Kind, outcome: Outcome, at: Date? = nil, detail: String? = nil) {
        self.kind = kind
        self.outcome = outcome
        self.at = at
        self.detail = detail
    }

    private enum CodingKeys: String, CodingKey {
        case kind, outcome, at, detail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        outcome = (try? container.decode(Outcome.self, forKey: .outcome)) ?? .succeeded
        at = try container.decodeIfPresent(Date.self, forKey: .at)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
    }
}

/// A specific delivery failure explanation that a recovery sheet can act on.
public struct CaptureDeliveryFailureReason: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case headingNotFound
        case vaultUnreachable
        case permissionDenied
        case other
    }

    public var kind: Kind
    /// The missing heading title, without leading `#` marks.
    public var headingTitle: String?
    public var headingLevel: Int?
    /// The vault-relative note that was being written, when known.
    public var relativeNotePath: String?

    public init(
        kind: Kind,
        headingTitle: String? = nil,
        headingLevel: Int? = nil,
        relativeNotePath: String? = nil
    ) {
        self.kind = kind
        self.headingTitle = headingTitle
        self.headingLevel = headingLevel
        self.relativeNotePath = relativeNotePath
    }

    private enum CodingKeys: String, CodingKey {
        case kind, headingTitle, headingLevel, relativeNotePath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? container.decode(Kind.self, forKey: .kind)) ?? .other
        headingTitle = try container.decodeIfPresent(String.self, forKey: .headingTitle)
        headingLevel = try container.decodeIfPresent(Int.self, forKey: .headingLevel)
        relativeNotePath = try container.decodeIfPresent(String.self, forKey: .relativeNotePath)
    }

    /// Markdown heading text such as `## Today`.
    public var headingMarkdown: String? {
        guard let headingTitle else { return nil }
        return String(repeating: "#", count: max(1, min(6, headingLevel ?? 2))) + " " + headingTitle
    }

    /// Classifies an underlying delivery error. Only route configuration (the
    /// heading selector) and the note path are retained, never the error text.
    public static func classify(
        _ error: Error,
        relativeNotePath: String? = nil
    ) -> CaptureDeliveryFailureReason {
        if let editorError = error as? MarkdownDocumentEditorError,
           case .headingNotFound(let selector) = editorError {
            return CaptureDeliveryFailureReason(
                kind: .headingNotFound,
                headingTitle: selector.title,
                headingLevel: selector.level,
                relativeNotePath: relativeNotePath
            )
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return CaptureDeliveryFailureReason(kind: .permissionDenied, relativeNotePath: relativeNotePath)
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError, NSFileReadUnknownError:
                return CaptureDeliveryFailureReason(kind: .vaultUnreachable, relativeNotePath: relativeNotePath)
            default:
                break
            }
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EPERM) || nsError.code == Int(EACCES) {
            return CaptureDeliveryFailureReason(kind: .permissionDenied, relativeNotePath: relativeNotePath)
        }
        return CaptureDeliveryFailureReason(kind: .other, relativeNotePath: relativeNotePath)
    }
}

/// Library-only content for one delivered capture: the exact Markdown entry
/// that was written and the vault-relative audio file. It lives in its own
/// file next to the privacy-limited history so Activity never reads it, and
/// it is removed whenever the matching Library row is deleted or cleared.
public struct CaptureLibraryContent: Codable, Equatable, Sendable, Identifiable {
    public var requestID: UUID
    /// The rendered entry exactly as delivered, including the heading it was
    /// placed under when the route uses one.
    public var renderedMarkdown: String?
    /// Plain captured text used for search, copy and re-delivery.
    public var text: String?
    /// The vault-relative path of the delivered recording, if any.
    public var audioRelativePath: String?
    public var audioDuration: TimeInterval?

    public var id: UUID { requestID }

    public init(
        requestID: UUID,
        renderedMarkdown: String? = nil,
        text: String? = nil,
        audioRelativePath: String? = nil,
        audioDuration: TimeInterval? = nil
    ) {
        self.requestID = requestID
        self.renderedMarkdown = renderedMarkdown
        self.text = text
        self.audioRelativePath = audioRelativePath
        self.audioDuration = audioDuration
    }

    public var audioFilename: String? {
        audioRelativePath.map { ($0 as NSString).lastPathComponent }
    }

    static let audioExtensions: Set<String> = ["m4a", "wav", "mp3", "aac", "caf", "aiff", "aif", "flac", "ogg", "opus", "mp4", "mov"]

    /// Builds content for a delivered request from its receipt.
    public static func make(
        request: CaptureRequest,
        receipt: CaptureReceipt,
        destination: CaptureDestination?,
        rootURL: URL
    ) -> CaptureLibraryContent {
        let audioURL = receipt.attachmentURLs.first {
            audioExtensions.contains($0.pathExtension.lowercased())
        }
        let audioPath = audioURL.flatMap {
            CaptureHistoryRecord.relativeNotePath(noteURL: $0, rootURL: rootURL)
        }
        var markdown = receipt.renderedEntry
        if let entry = markdown,
           let heading = destination.flatMap({ CaptureHistoryRecord.placementHeadingMarkdown(for: $0.placement) }) {
            markdown = heading + "\n" + entry
        }
        return CaptureLibraryContent(
            requestID: request.id,
            renderedMarkdown: markdown,
            text: plainText(of: request),
            audioRelativePath: audioPath
        )
    }

    public static func plainText(of request: CaptureRequest) -> String? {
        let parts: [String] = request.payloads.compactMap { payload in
            switch payload {
            case .text(let text):
                return text
            case .url(let url, let title):
                return title.map { "[\($0)](\(url.absoluteString))" } ?? url.absoluteString
            case .audio(_, let transcript):
                return transcript
            case .scannedDocument(_, _, let extracted):
                return extracted
            case .retainedAudio, .image, .file, .sketch:
                return nil
            }
        }
        let joined = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return joined.isEmpty ? nil : joined
    }
}

extension CaptureHistoryRecord {
    /// The heading title used by a beneath-heading placement.
    public static func placementHeading(for placement: CapturePlacement) -> String? {
        if case .beneathHeading(let selector, _, _) = placement { return selector.title }
        return nil
    }

    static func placementHeadingMarkdown(for placement: CapturePlacement) -> String? {
        guard case .beneathHeading(let selector, _, _) = placement else { return nil }
        return String(repeating: "#", count: max(1, min(6, selector.level ?? 2))) + " " + selector.title
    }

    /// A status-only route log for one delivery attempt.
    public static func routeLog(
        for request: CaptureRequest,
        outcome: CaptureHistoryOutcome,
        at date: Date = Date(),
        relativeNotePath: String? = nil,
        failureCategory: CaptureHistoryFailureCategory? = nil,
        failureReason: CaptureDeliveryFailureReason? = nil
    ) -> [CaptureRouteLogStep] {
        var steps: [CaptureRouteLogStep] = [
            CaptureRouteLogStep(kind: .capture, outcome: .succeeded, at: request.createdAt, detail: request.source.rawValue)
        ]
        switch request.voxProcessingState {
        case .applied:
            steps.append(CaptureRouteLogStep(kind: .process, outcome: .succeeded, at: date))
        case .pending:
            steps.append(CaptureRouteLogStep(kind: .process, outcome: outcome == .failed ? .failed : .skipped, at: date))
        case .notRequested:
            steps.append(CaptureRouteLogStep(kind: .process, outcome: .skipped))
        }
        let shapeFailed = outcome == .failed && failureCategory == .invalidRequest
        steps.append(CaptureRouteLogStep(kind: .shape, outcome: shapeFailed ? .failed : .succeeded, at: date))
        if outcome == .delivered {
            steps.append(CaptureRouteLogStep(kind: .deliver, outcome: .succeeded, at: date, detail: relativeNotePath))
        } else if !shapeFailed {
            let detail: String?
            if failureReason?.kind == .headingNotFound, let heading = failureReason?.headingMarkdown {
                detail = "Heading not found: \(heading)"
            } else {
                detail = failureCategory?.displayName
            }
            steps.append(CaptureRouteLogStep(kind: .deliver, outcome: .failed, at: date, detail: detail))
        }
        return steps
    }

    /// Returns a copy with route-log, heading and failure-reason details.
    public func withDeliveryDetails(
        request: CaptureRequest,
        placement: CapturePlacement?,
        error: Error? = nil,
        attemptedNotePath: String? = nil
    ) -> CaptureHistoryRecord {
        var copy = self
        copy.placementHeading = placement.flatMap(Self.placementHeading(for:))
        if let error {
            var reason = CaptureDeliveryFailureReason.classify(
                error,
                relativeNotePath: attemptedNotePath ?? relativeNotePath
            )
            if reason.kind == .other, failureCategory == .destinationUnavailable {
                reason.kind = .vaultUnreachable
            }
            if reason.kind == .other, failureCategory == .permissionDenied {
                reason.kind = .permissionDenied
            }
            if let path = reason.relativeNotePath,
               (try? CapturePathValidation.validateRelativePath(path)) == nil {
                reason.relativeNotePath = nil
            }
            copy.failureReason = reason
        }
        copy.routeLog = Self.routeLog(
            for: request,
            outcome: outcome,
            at: deliveredAt ?? Date(),
            relativeNotePath: relativeNotePath,
            failureCategory: failureCategory,
            failureReason: copy.failureReason
        )
        return copy
    }
}
