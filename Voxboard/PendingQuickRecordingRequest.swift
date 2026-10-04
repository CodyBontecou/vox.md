import Foundation
import VoxboardShared

/// Shared launch metadata for the existing foreground one-shot recording path.
/// A missing draft override means legacy immediate delivery; `false` still means
/// draft delivery, just without an audio attachment. Never infer this policy
/// from the composer's persisted result-mode preference.
struct PendingQuickRecordingRequest: Equatable {
    let requestedFlowID: String?
    let draftAttachAudio: Bool?

    func persist(defaults: UserDefaults? = AppConstants.sharedDefaults) {
        if let requestedFlowID, !requestedFlowID.isEmpty {
            defaults?.set(requestedFlowID, forKey: AppConstants.pendingWidgetRecordFlowIdKey)
        } else {
            defaults?.removeObject(forKey: AppConstants.pendingWidgetRecordFlowIdKey)
        }
        if let draftAttachAudio {
            defaults?.set(draftAttachAudio, forKey: AppConstants.pendingWidgetRecordDraftAttachAudioKey)
        } else {
            defaults?.removeObject(forKey: AppConstants.pendingWidgetRecordDraftAttachAudioKey)
        }
        // Publish last, after the preset and delivery policy are both present.
        defaults?.set(true, forKey: AppConstants.pendingWidgetRecordKey)
    }

    /// The app has already transferred the pending flag into its scene binding.
    /// Consume the launch's policy once, before asynchronous draft loading.
    static func consume(defaults: UserDefaults? = AppConstants.sharedDefaults) -> Self {
        let request = Self(
            requestedFlowID: defaults?.string(forKey: AppConstants.pendingWidgetRecordFlowIdKey),
            // A malformed override may drop the attachment, never the review step.
            draftAttachAudio: defaults?.object(forKey: AppConstants.pendingWidgetRecordDraftAttachAudioKey)
                .map { $0 as? Bool ?? false }
        )
        defaults?.removeObject(forKey: AppConstants.pendingWidgetRecordFlowIdKey)
        defaults?.removeObject(forKey: AppConstants.pendingWidgetRecordDraftAttachAudioKey)
        return request
    }
}
