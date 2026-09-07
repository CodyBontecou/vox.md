import Foundation

public protocol CaptureImageDescribing: Sendable {
    func describe(
        asset: CaptureAssetReference,
        assetRootURL: URL,
        localeIdentifier: String
    ) async throws -> String?
}

public enum CaptureImageDescription {
    public static let maximumLength = 300

    public static func validated(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maximumLength,
              !text.contains("\n"), !text.contains("\r"),
              !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return text
    }
}

public extension CapturePresetProfile {
    var processesText: Bool {
        captureProcessingEnabled && postProcessingMode != .none
            && resolvedPostProcessingInstruction != nil
    }

    var processesImages: Bool { captureProcessingEnabled && generateImageAltText }

    func processingState(for payloads: [CapturePayload]) -> CapturePresetProcessingState {
        let pending = payloads.contains { payload in
            switch payload {
            case .text, .scannedDocument:
                return processesText && captureProcessingScope.appliesToTypedText
            case .audio:
                return processesText && captureProcessingScope.appliesToVoice
            case .image(_, let text, let origin), .sketch(_, _, let text, let origin):
                return processesImages && CaptureAltTextOrigin.needsDescription(text: text, origin: origin)
            case .url, .retainedAudio, .file:
                return false
            }
        }
        return pending ? .pending : .applied
    }
}

/// Reads the immutable staged asset without following file or directory symlinks.
/// The image decoder operates on these bounded bytes, never on an external URL.
public enum CaptureImageAssetReader {
    public static let maximumByteCount = 25 * 1_024 * 1_024

    public static func read(asset: CaptureAssetReference, rootURL: URL) throws -> Data? {
        try SecureCaptureFileIO.read(
            relativePath: asset.relativePath,
            rootURL: rootURL,
            maximumByteCount: maximumByteCount
        )
    }
}
