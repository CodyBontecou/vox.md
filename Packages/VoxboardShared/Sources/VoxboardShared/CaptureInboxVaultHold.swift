import Foundation
import VoxboardCaptureCore

/// Holds a composer capture on this device when its vault folder can't be
/// reached (stale bookmark, revoked access, folder gone).
///
/// The capture becomes a durable inbox request, exactly like a Share
/// extension capture that could not be delivered: its staged attachments are
/// copied into `inbox-staging/<request id>/`, the request is parked in the
/// `failed` state, and a failed history record with the `vaultUnreachable`
/// reason makes it appear in Activity as "Can't reach your vault". Re-granting
/// folder access retries failed requests and drains the inbox.
public enum CaptureInboxVaultHold {
    /// - Parameters:
    ///   - request: the processed request the composer was about to deliver.
    ///     Its asset references are relative to `stagedAssetRootURL`.
    ///   - stagedAssetRootURL: the draft's staging folder.
    ///   - destinationName: shown in the failure record.
    /// - Returns: the held request's ID (the request's own ID, so a later
    ///   retry can never duplicate the note entry).
    @discardableResult
    public static func hold(
        _ request: CaptureRequest,
        stagedAssetRootURL: URL,
        destinationName: String,
        captureRootURL: URL,
        defaults: UserDefaults? = AppConstants.sharedDefaults,
        coordinator: any CaptureFileCoordinating = NSFileCoordinatorCaptureFileCoordinator.shared,
        fileManager: FileManager = .default
    ) async throws -> UUID {
        let inbox = CaptureInbox(rootDirectoryURL: captureRootURL, coordinator: coordinator)
        let held = try rebasingAssets(
            of: request,
            from: stagedAssetRootURL,
            captureRootURL: captureRootURL,
            fileManager: fileManager
        )
        try await inbox.enqueue(held)
        guard let claimed = try await inbox.claim(requestID: held.id) else { return held.id }

        let library = try? await CapturePresetRouteLibrary.load(
            from: CaptureLibraryStore(
                fileURL: captureRootURL.appendingPathComponent(CaptureLibraryStore.defaultFilename),
                coordinator: coordinator
            ),
            defaults: defaults
        )
        let error = ConfiguredTranscriptCaptureError.staleDestination(destinationName)
        let attempted = library.flatMap { library in
            library.destinations.first(where: { $0.id == claimed.destinationID }).map {
                CaptureInboxDeliveryService.attemptedDelivery(request: claimed, destination: $0, library: library)
            }
        }
        if let record = try? CaptureHistoryRecord(
            requestID: claimed.id,
            createdAt: claimed.createdAt,
            deliveredAt: Date(),
            source: claimed.source,
            outcome: .failed,
            destinationID: claimed.destinationID,
            destinationName: destinationName,
            voxID: claimed.voxReference?.id,
            voxName: claimed.voxReference?.name,
            relativeNotePath: nil,
            attachmentCount: assetReferences(in: claimed).count,
            failureCategory: .destinationUnavailable
        ) {
            _ = await CaptureHistoryStore(
                fileURL: captureRootURL.appendingPathComponent(AppConstants.captureHistoryFilename),
                coordinator: coordinator
            ).upsertBestEffort(record.withDeliveryDetails(
                request: claimed,
                placement: attempted?.placement,
                error: error,
                attemptedNotePath: attempted?.notePath
            ))
        }
        try await inbox.fail(requestID: claimed.id)
        return claimed.id
    }

    /// Copies every staged asset into the inbox staging folder for the
    /// request and rewrites the references relative to `captureRootURL`, the
    /// asset root inbox delivery uses.
    static func rebasingAssets(
        of request: CaptureRequest,
        from stagedAssetRootURL: URL,
        captureRootURL: URL,
        fileManager: FileManager = .default
    ) throws -> CaptureRequest {
        let relativeFolder = "inbox-staging/\(request.id.uuidString.lowercased())"
        var copied: [String: CaptureAssetReference] = [:]
        func rebase(_ reference: CaptureAssetReference) throws -> CaptureAssetReference {
            if let done = copied[reference.relativePath] { return done }
            let source = try CapturePathValidation.containedFileURL(
                relativePath: reference.relativePath,
                rootURL: stagedAssetRootURL
            )
            let newRelativePath = "\(relativeFolder)/\(reference.relativePath)"
            let target = try CapturePathValidation.containedFileURL(
                relativePath: newRelativePath,
                rootURL: captureRootURL
            )
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: source, to: target)
            var rebased = reference
            rebased.relativePath = newRelativePath
            copied[reference.relativePath] = rebased
            return rebased
        }
        var result = request
        result.payloads = try request.payloads.map { payload in
            switch payload {
            case .text, .url:
                return payload
            case .audio(let asset, let transcript):
                return .audio(try rebase(asset), transcript: transcript)
            case .retainedAudio(let asset, let placement):
                return .retainedAudio(try rebase(asset), embedPlacement: placement)
            case .image(let asset, let altText, let origin):
                return .image(try rebase(asset), altText: altText, altTextOrigin: origin)
            case .file(let asset):
                return .file(try rebase(asset))
            case .scannedDocument(let pages, let pdf, let text):
                return .scannedDocument(
                    pages: try pages.map(rebase),
                    pdf: try pdf.map(rebase),
                    extractedText: text
                )
            case .sketch(let drawing, let preview, let altText, let origin):
                return .sketch(
                    drawing: try rebase(drawing),
                    preview: try rebase(preview),
                    altText: altText,
                    altTextOrigin: origin
                )
            }
        }
        return result
    }

    static func assetReferences(in request: CaptureRequest) -> [CaptureAssetReference] {
        request.payloads.flatMap { payload -> [CaptureAssetReference] in
            switch payload {
            case .text, .url: []
            case .audio(let asset, _), .retainedAudio(let asset, _), .image(let asset, _, _), .file(let asset): [asset]
            case .scannedDocument(let pages, let pdf, _): pages + (pdf.map { [$0] } ?? [])
            case .sketch(let drawing, let preview, _, _): [drawing, preview]
            }
        }
    }
}
