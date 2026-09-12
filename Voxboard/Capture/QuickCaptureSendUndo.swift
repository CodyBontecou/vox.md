import Foundation
import UniformTypeIdentifiers
import VoxboardShared

/// A value snapshot of the Capture that just finished sending.
///
/// Value-backed payloads can be retained directly. Delivery moves staged files,
/// so audio is first hard-linked (or copied when linking is unavailable) into a
/// short-lived cache owned by the Undo snapshot.
struct SentCaptureUndoSnapshot: Equatable {
    let id: UUID
    let requestID: UUID
    let text: String
    let restorablePayloads: [CapturePayload]
    let cachedAudioPayloads: [CapturePayload]
    let sentAttachmentCount: Int
    let presetDisplayName: String
    let audioCacheDirectoryURL: URL?

    init(
        id: UUID = UUID(),
        requestID: UUID,
        text: String,
        restorablePayloads: [CapturePayload],
        cachedAudioPayloads: [CapturePayload] = [],
        sentAttachmentCount: Int,
        presetDisplayName: String,
        audioCacheDirectoryURL: URL? = nil
    ) {
        self.id = id
        self.requestID = requestID
        self.text = text
        self.restorablePayloads = restorablePayloads
        self.cachedAudioPayloads = cachedAudioPayloads
        self.sentAttachmentCount = sentAttachmentCount
        self.presetDisplayName = presetDisplayName
        self.audioCacheDirectoryURL = audioCacheDirectoryURL
    }

    var offersUndo: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !restorablePayloads.isEmpty
            || !cachedAudioPayloads.isEmpty
    }

    var summaryText: String {
        if sentAttachmentCount > 0 {
            return sentAttachmentCount == 1
                ? String(localized: "Capture and attachment sent to \(presetDisplayName)")
                : String(localized: "Capture and attachments sent to \(presetDisplayName)")
        }
        return String(localized: "Capture sent to \(presetDisplayName)")
    }

    func discardCachedAudio(fileManager: FileManager = .default) {
        guard let audioCacheDirectoryURL else { return }
        try? fileManager.removeItem(at: audioCacheDirectoryURL)
    }
}

enum SentCaptureUndo {
    static let toastWindow: Duration = .seconds(5)
    static let audioCacheDirectoryName = "sent-undo-audio"

    static func audioCacheRootURL(captureRootURL: URL?) -> URL? {
        captureRootURL?.appendingPathComponent(audioCacheDirectoryName, isDirectory: true)
    }

    /// No Undo window survives a process restart, so no audio cache should.
    static func discardAbandonedAudioCache(
        captureRootURL: URL?,
        fileManager: FileManager = .default
    ) {
        guard let rootURL = audioCacheRootURL(captureRootURL: captureRootURL) else { return }
        try? fileManager.removeItem(at: rootURL)
    }

    static func snapshot(
        draft: CaptureDraft,
        presetDisplayName: String,
        stagingDirectoryURL: URL? = nil,
        audioCacheRootURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> SentCaptureUndoSnapshot {
        let snapshotID = UUID()
        let cached = cacheAudioPayloads(
            in: draft.additionalPayloads,
            snapshotID: snapshotID,
            sourceDirectoryURL: stagingDirectoryURL,
            cacheRootURL: audioCacheRootURL,
            fileManager: fileManager
        )
        return SentCaptureUndoSnapshot(
            id: snapshotID,
            requestID: draft.requestID,
            text: draft.text,
            restorablePayloads: draft.additionalPayloads.filter(\.isRestorableAfterSend),
            cachedAudioPayloads: cached.payloads,
            sentAttachmentCount: draft.additionalPayloads.count,
            presetDisplayName: presetDisplayName,
            audioCacheDirectoryURL: cached.directoryURL
        )
    }

    static func snapshot(
        requestID: UUID,
        text: String,
        recordedAudioURL: URL,
        originalFilename: String? = nil,
        presetDisplayName: String,
        audioCacheRootURL: URL?,
        fileManager: FileManager = .default
    ) -> SentCaptureUndoSnapshot {
        let safeOriginalFilename = CaptureAssetStager.sanitizedFilename(
            originalFilename ?? recordedAudioURL.lastPathComponent,
            fallbackExtension: recordedAudioURL.pathExtension.isEmpty ? "wav" : recordedAudioURL.pathExtension
        )
        let contentTypeIdentifier = UTType(filenameExtension: recordedAudioURL.pathExtension)?.identifier
            ?? UTType.audio.identifier
        let byteCount = (try? recordedAudioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .map(Int64.init)
        let asset = try? CaptureAssetReference(
            relativePath: recordedAudioURL.lastPathComponent,
            originalFilename: safeOriginalFilename,
            contentTypeIdentifier: contentTypeIdentifier,
            byteCount: byteCount
        )
        let draft = CaptureDraft(
            requestID: requestID,
            text: text,
            additionalPayloads: asset.map { [.audio($0, transcript: nil)] } ?? []
        )
        return snapshot(
            draft: draft,
            presetDisplayName: presetDisplayName,
            stagingDirectoryURL: recordedAudioURL.deletingLastPathComponent(),
            audioCacheRootURL: audioCacheRootURL,
            fileManager: fileManager
        )
    }

    static func apply(
        _ snapshot: SentCaptureUndoSnapshot,
        to viewModel: QuickCaptureViewModel
    ) async -> Bool {
        defer { snapshot.discardCachedAudio() }
        guard snapshot.offersUndo,
              !viewModel.hasLiveRecordedTranscriptPreview else { return false }
        return await viewModel.restoreSentCapture(
            text: snapshot.text,
            valuePayloads: snapshot.restorablePayloads,
            cachedAudioPayloads: snapshot.cachedAudioPayloads,
            audioCacheDirectoryURL: snapshot.audioCacheDirectoryURL
        )
    }

    private static func cacheAudioPayloads(
        in payloads: [CapturePayload],
        snapshotID: UUID,
        sourceDirectoryURL: URL?,
        cacheRootURL: URL?,
        fileManager: FileManager
    ) -> (payloads: [CapturePayload], directoryURL: URL?) {
        let audioPayloads = payloads.filter(\.isAudioPayload)
        guard !audioPayloads.isEmpty,
              let sourceDirectoryURL,
              let cacheRootURL else { return ([], nil) }

        let cacheDirectoryURL = cacheRootURL
            .appendingPathComponent(snapshotID.uuidString.lowercased(), isDirectory: true)
        do {
            try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
            var cachedPayloads: [CapturePayload] = []
            for (index, payload) in audioPayloads.enumerated() {
                guard let sourceAsset = payload.audioAsset else { continue }
                let sourceURL = try CapturePathValidation.containedFileURL(
                    relativePath: sourceAsset.relativePath,
                    rootURL: sourceDirectoryURL
                )
                let sourceExtension = sourceURL.pathExtension
                let cacheFilename = sourceExtension.isEmpty
                    ? "audio-\(index + 1)"
                    : "audio-\(index + 1).\(sourceExtension)"
                let cachedURL = cacheDirectoryURL.appendingPathComponent(cacheFilename)
                do {
                    try fileManager.linkItem(at: sourceURL, to: cachedURL)
                } catch {
                    try fileManager.copyItem(at: sourceURL, to: cachedURL)
                }
                let cachedSize = (try? cachedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                    .map(Int64.init)
                let cachedAsset = try CaptureAssetReference(
                    relativePath: cacheFilename,
                    originalFilename: sourceAsset.originalFilename,
                    contentTypeIdentifier: sourceAsset.contentTypeIdentifier,
                    byteCount: cachedSize ?? sourceAsset.byteCount
                )
                cachedPayloads.append(payload.replacingAudioAsset(with: cachedAsset))
            }
            guard cachedPayloads.count == audioPayloads.count else {
                throw SentCaptureUndoCacheError.incompleteAudioCache
            }
            return (cachedPayloads, cacheDirectoryURL)
        } catch {
            try? fileManager.removeItem(at: cacheDirectoryURL)
            return ([], nil)
        }
    }
}

private enum SentCaptureUndoCacheError: Error {
    case incompleteAudioCache
}

extension CapturePayload {
    var isRestorableAfterSend: Bool {
        switch self {
        case .text, .url:
            return true
        case .audio, .retainedAudio, .image, .file, .scannedDocument, .sketch:
            return false
        }
    }

    var isAudioPayload: Bool {
        switch self {
        case .audio, .retainedAudio:
            return true
        case .text, .url, .image, .file, .scannedDocument, .sketch:
            return false
        }
    }

    var audioAsset: CaptureAssetReference? {
        switch self {
        case .audio(let asset, _), .retainedAudio(let asset, _):
            return asset
        case .text, .url, .image, .file, .scannedDocument, .sketch:
            return nil
        }
    }

    func replacingAudioAsset(with asset: CaptureAssetReference) -> CapturePayload {
        switch self {
        case .audio(_, let transcript):
            return .audio(asset, transcript: transcript)
        case .retainedAudio(_, let embedPlacement):
            return .retainedAudio(asset, embedPlacement: embedPlacement)
        case .text, .url, .image, .file, .scannedDocument, .sketch:
            return self
        }
    }
}
