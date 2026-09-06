import Foundation
import VoxboardShared

/// Snapshot of a just-sent Capture kept alive for the sent-toast undo window.
///
/// Restoring only puts the outgoing content back into the quick-capture
/// composer as an editable draft. The note that was already written to the
/// user's vault is intentionally left untouched — reversing vault writes is
/// out of scope for this feature, and the user can delete the sent note
/// themselves.
struct SentCaptureUndoSnapshot: Equatable {
    /// Matches the `CaptureReceipt.requestID` produced by the send, so an
    /// undo offer is only kept when the receipt belongs to the composer
    /// send that created the snapshot.
    let requestID: UUID
    let text: String
    /// Value-based payloads (text/link) that can round-trip back into a
    /// draft without restaging files. Asset-backed payloads are counted for
    /// messaging but not restored, because delivery moves their files into
    /// the destination note.
    let restorablePayloads: [CapturePayload]
    let sentAttachmentCount: Int
    let presetDisplayName: String

    var offersUndo: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !restorablePayloads.isEmpty
    }
}

@MainActor
enum SentCaptureUndo {
    /// How long the sent toast keeps its Undo action available.
    static let toastWindow: Duration = .seconds(5)

    /// Must be called before `QuickCaptureViewModel.submit()` clears the
    /// live draft: this is the only moment the outgoing text still exists.
    static func snapshot(draft: CaptureDraft, presetDisplayName: String) -> SentCaptureUndoSnapshot {
        SentCaptureUndoSnapshot(
            requestID: draft.requestID,
            text: draft.text,
            restorablePayloads: draft.additionalPayloads.filter(\.isRestorableAfterSend),
            sentAttachmentCount: draft.additionalPayloads.count,
            presetDisplayName: presetDisplayName
        )
    }

    /// Restores the snapshot into the live composer draft. Any content the
    /// user typed after the send is preserved by appending; undo never
    /// discards newer input.
    static func apply(_ snapshot: SentCaptureUndoSnapshot, to viewModel: QuickCaptureViewModel) async -> Bool {
        guard snapshot.offersUndo else { return false }
        guard !viewModel.hasLiveRecordedTranscriptPreview else {
            viewModel.errorMessage = String(
                localized: "Finish the current recording before restoring the sent Capture."
            )
            return false
        }
        let now = Date()
        let restoredText = snapshot.text.trimmingCharacters(in: .newlines)
        if viewModel.draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            viewModel.draft.text = restoredText
        } else if !restoredText.isEmpty {
            viewModel.draft.text += "\n\n" + restoredText
        }
        viewModel.draft.additionalPayloads.append(contentsOf: snapshot.restorablePayloads)
        viewModel.draft.updatedAt = now
        viewModel.draft.beginCaptureIfNeeded(at: now)
        await viewModel.saveDraftNow()
        return true
    }
}

extension CapturePayload {
    /// Text and link payloads are pure values; media assets are moved into
    /// the delivered note and cannot be restored without re-staging files.
    var isRestorableAfterSend: Bool {
        switch self {
        case .text, .url:
            return true
        case .audio, .retainedAudio, .image, .file, .scannedDocument, .sketch:
            return false
        }
    }
}
