import Foundation

/// An in-memory decision, never a second persisted draft. Keep the complete
/// launch value until acceptance; nothing from it enters the composer early.
public struct CapturePresetSwitchConfirmation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let incoming: CaptureDeepLinkDraft
    public let presetName: String
    private let originalDraft: CaptureDraft
    private let originalInput: CaptureRequestedInput?

    public init(
        id: UUID = UUID(),
        incoming: CaptureDeepLinkDraft,
        presetName: String,
        draft: CaptureDraft,
        requestedInput: CaptureRequestedInput?
    ) {
        self.id = id
        self.incoming = incoming
        self.presetName = presetName
        self.originalDraft = draft
        self.originalInput = requestedInput
    }

    /// Typing/attachments and autosave timestamps may advance while deciding.
    /// A new draft/request, changed route, provenance or privacy journal must
    /// instead require a new invocation. Acceptance appends to the latest text.
    public func matches(draft: CaptureDraft, requestedInput: CaptureRequestedInput?) -> Bool {
        draft.id == originalDraft.id
            && draft.requestID == originalDraft.requestID
            && draft.voxID == originalDraft.voxID
            && draft.destinationSelectionMode == originalDraft.destinationSelectionMode
            && draft.destinationID == originalDraft.destinationID
            && draft.relativeNotePathOverride == originalDraft.relativeNotePathOverride
            && draft.placementOverride == originalDraft.placementOverride
            && draft.entryTemplateID == originalDraft.entryTemplateID
            && draft.voxProfileSnapshot == originalDraft.voxProfileSnapshot
            && draft.locationOutcome == originalDraft.locationOutcome
            && draft.locationDecisionOverride == originalDraft.locationDecisionOverride
            && draft.captureSource == originalDraft.captureSource
            && requestedInput == originalInput
    }
}
