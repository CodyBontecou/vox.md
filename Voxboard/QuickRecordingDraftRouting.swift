import Foundation
import VoxboardShared

extension PendingQuickRecordingRequest {
    func completionMode(flowID: String) -> RecordingCompletionMode {
        if let draftAttachAudio {
            return .captureDraft(attachAudio: draftAttachAudio)
        }
        return .runVox(flowID: flowID)
    }

    func draftRequestID(in draft: CaptureDraft) -> UUID? {
        draftAttachAudio == nil ? nil : draft.requestID
    }
}

/// The recorder's draft-only sink. It deliberately has no export/Send API.
/// Loading before the identity check also protects cold-launch queue recovery:
/// the allocated view model's placeholder draft is not the durable target.
@MainActor
enum CaptureDraftRecordingEventDelivery {
    static func deliver(
        _ event: CaptureDraftRecordingEvent,
        to viewModel: QuickCaptureViewModel
    ) async -> Bool {
        switch event {
        case .origin(let source, let locationOutcome, let profileSnapshot):
            return await viewModel.journalRecordedOrigin(
                source: source,
                outcome: locationOutcome,
                profileSnapshot: profileSnapshot
            )
        case .clearOrigin(let profileID):
            return await viewModel.clearRecordedOrigin(profileID: profileID)
        case .audio(let url, let draftRequestID, let deliveryID):
            await viewModel.load()
            guard draftRequestID == nil || viewModel.draft.requestID == draftRequestID else { return false }
            return await viewModel.stageRecordedAudio(at: url, deliveryID: deliveryID) != nil
        case .liveTranscript(let sessionID, let finalizedText, let volatileText):
            await viewModel.updateLiveRecordedTranscript(
                sessionID: sessionID,
                finalizedText: finalizedText,
                volatileText: volatileText
            )
            return true
        case .cancelLiveTranscript(let sessionID):
            await viewModel.cancelLiveRecordedTranscript(sessionID: sessionID)
            return true
        case .transcript(let text, let draftRequestID, let liveSessionID, let deliveryID):
            await viewModel.load()
            guard draftRequestID == nil || viewModel.draft.requestID == draftRequestID else { return false }
            return await viewModel.appendRecordedTranscript(
                text,
                sessionID: liveSessionID,
                deliveryID: deliveryID
            )
        }
    }
}
