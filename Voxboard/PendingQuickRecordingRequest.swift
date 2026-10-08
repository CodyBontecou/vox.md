import Foundation
import VoxboardShared

/// Shared launch metadata for the existing foreground one-shot recording path.
/// A missing draft override means legacy immediate delivery; `false` still means
/// draft delivery, just without an audio attachment. Never infer this policy
/// from the composer's persisted result-mode preference.
struct PendingQuickRecordingRequest: Equatable {
    static let didPersistNotification = Notification.Name("Voxboard.pendingQuickRecordingRequest")

    let requestedFlowID: String?
    let draftAttachAudio: Bool?
    let recordingAction: RecordingAction

    init(requestedFlowID: String?, draftAttachAudio: Bool?, recordingAction: RecordingAction = .start) {
        self.requestedFlowID = requestedFlowID
        self.draftAttachAudio = draftAttachAudio
        self.recordingAction = recordingAction
    }

    func persist(
        defaults: UserDefaults? = AppConstants.sharedDefaults,
        notificationCenter: NotificationCenter = .default
    ) {
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
        WidgetRecordingActionSelection.persist(recordingAction, defaults: defaults)
        // Publish last, after the preset and delivery policy are both present.
        defaults?.set(true, forKey: AppConstants.pendingWidgetRecordKey)
        // Foreground intents may execute after the scene is already active.
        // Wake its consumer now; the durable flag also covers launches before
        // the app subscribes and requests written by another process.
        notificationCenter.post(name: Self.didPersistNotification, object: nil)
    }

    /// The app has already transferred the pending flag into its scene binding.
    /// Consume the launch's policy once, before asynchronous draft loading.
    static func consume(defaults: UserDefaults? = AppConstants.sharedDefaults) -> Self {
        let request = Self(
            requestedFlowID: defaults?.string(forKey: AppConstants.pendingWidgetRecordFlowIdKey),
            // A malformed override may drop the attachment, never the review step.
            draftAttachAudio: defaults?.object(forKey: AppConstants.pendingWidgetRecordDraftAttachAudioKey)
                .map { $0 as? Bool ?? false },
            recordingAction: WidgetRecordingActionSelection.consume(defaults: defaults)
        )
        defaults?.removeObject(forKey: AppConstants.pendingWidgetRecordFlowIdKey)
        defaults?.removeObject(forKey: AppConstants.pendingWidgetRecordDraftAttachAudioKey)
        return request
    }
}
