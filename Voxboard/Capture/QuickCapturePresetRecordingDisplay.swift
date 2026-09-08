import Foundation

/// A display-only value copied from the recording's immutable delivery origin,
/// never from the composer's current selection or a fresh preset-store lookup.
/// Optional identity is deliberate: an unavailable snapshot must not name an
/// unrelated current preset. This value cannot change recording/draft routing.
enum QuickCapturePresetRecordingDisplay: Equatable, Sendable {
    case draft
    case preset(id: String?, name: String?)

    var transcribingSubtitle: String {
        switch self {
        case .draft:
            return String(localized: "Adding transcript to this Capture")
        case .preset(_, let name):
            guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return String(localized: "Running Capture Preset")
            }
            return String(localized: "Running \(name)")
        }
    }
}
