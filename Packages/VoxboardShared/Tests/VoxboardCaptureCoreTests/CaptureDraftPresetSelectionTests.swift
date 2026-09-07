import XCTest
@testable import VoxboardCaptureCore

final class CaptureDraftPresetSelectionTests: XCTestCase {
    func testSamePresetIsFullValueAndEncodingNoOp() throws {
        let original = try makeDraft()
        var draft = original
        draft.selectVox("journal")
        XCTAssertEqual(draft, original)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(draft), try encoder.encode(original))
    }

    func testDifferentPresetResetsOnlyRouteAndPrivacy() throws {
        let original = try makeDraft()
        let request = try original.makeRequest(source: .app)
        var draft = original
        draft.selectVox("inbox")

        var expected = original
        expected.voxID = "inbox"
        expected.destinationSelectionMode = .inherited
        expected.destinationID = nil
        expected.relativeNotePathOverride = nil
        expected.placementOverride = nil
        expected.entryTemplateID = nil
        expected.voxProfileSnapshot = nil
        expected.locationOutcome = nil
        expected.locationDecisionOverride = nil
        XCTAssertEqual(draft, expected)
        XCTAssertEqual(draft.text, original.text)
        XCTAssertEqual(draft.additionalPayloads, original.additionalPayloads)
        XCTAssertEqual(draft.requestID, original.requestID)
        XCTAssertEqual(draft.captureStartedAt, original.captureStartedAt)
        // Value snapshots already queued/completed are never mutated.
        XCTAssertEqual(request.voxProfile, original.voxProfileSnapshot)
        XCTAssertEqual(request.locationOutcome, original.locationOutcome)
        XCTAssertEqual(request.destinationID, original.destinationID)
    }

    func testExplicitDefaultsRemainSeparateFromSamePresetSelection() throws {
        var draft = try makeDraft()
        draft.selectVox("journal")
        XCTAssertNotNil(draft.relativeNotePathOverride)
        draft.useInheritedDestination()
        XCTAssertEqual(draft.destinationSelectionMode, .inherited)
        XCTAssertNil(draft.destinationID)
        XCTAssertNil(draft.relativeNotePathOverride)
        // This low-level destination operation doesn't rewrite origin privacy.
        XCTAssertNotNil(draft.voxProfileSnapshot)
    }

    func testConfirmationRetainsWholeLaunchAndAllowsTypingAndAutosave() throws {
        var draft = try makeDraft()
        let incoming = CaptureDeepLinkDraft(
            text: "Incoming", url: URL(string: "https://example.com/launch"),
            destinationID: UUID(), voxID: "inbox", requestedInput: .camera, source: .widget
        )
        let pending = CapturePresetSwitchConfirmation(
            incoming: incoming, presetName: "Inbox", draft: draft, requestedInput: .files
        )
        draft.text += "\nTyped while deciding"
        draft.updatedAt = Date(timeIntervalSince1970: 9_999)
        draft.additionalPayloads.append(.text("New attachment"))
        XCTAssertEqual(pending.incoming, incoming)
        XCTAssertTrue(pending.matches(draft: draft, requestedInput: .files))
    }

    func testConfirmationRejectsChangedIdentityRoutePrivacySourceOrInput() throws {
        let draft = try makeDraft()
        let pending = CapturePresetSwitchConfirmation(
            incoming: CaptureDeepLinkDraft(voxID: "inbox", source: .widget),
            presetName: "Inbox", draft: draft, requestedInput: .photos
        )
        let mutations: [(inout CaptureDraft) -> Void] = [
            { $0.id = UUID() }, { $0.requestID = UUID() }, { $0.voxID = "other" },
            { $0.destinationID = UUID() }, { $0.useInheritedDestination() },
            { $0.relativeNotePathOverride = "Changed.md" }, { $0.placementOverride = .append },
            { $0.entryTemplateID = nil }, { $0.voxProfileSnapshot = nil },
            { $0.locationOutcome = nil }, { $0.locationDecisionOverride = nil },
            { $0.captureSource = .app },
        ]
        for mutate in mutations {
            var changed = draft
            mutate(&changed)
            XCTAssertFalse(pending.matches(draft: changed, requestedInput: .photos))
        }
        XCTAssertFalse(pending.matches(draft: draft, requestedInput: .voice))
    }

    private func makeDraft() throws -> CaptureDraft {
        let asset = try CaptureAssetReference(
            relativePath: "photo.jpg", originalFilename: "photo.jpg", contentTypeIdentifier: "public.jpeg"
        )
        let transcriptID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        return CaptureDraft(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            requestID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            captureStartedAt: Date(timeIntervalSince1970: 150),
            text: "    Markdown  \nDraft 📝", voxID: "journal",
            voxProfileSnapshot: CapturePresetProfile(
                id: "journal", name: "Origin", symbolName: "book",
                locationPolicy: CapturePresetLocationPolicy(isEnabled: true, precision: .city)
            ),
            destinationID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            captureSource: .widget,
            locationOutcome: .unavailable(.timeout, attemptedAt: Date(timeIntervalSince1970: 175)),
            locationDecisionOverride: .sendWithoutLocation,
            deliveryKind: .meteredVoiceTranscript,
            placementOverride: .prepend, relativeNotePathOverride: "Notes/One-off.md",
            entryTemplateID: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            additionalPayloads: [.image(asset, altText: "Photo"), .audio(asset, transcript: "Transcript")],
            stagedRecordingAudioReceipts: [transcriptID.uuidString: asset],
            appliedRecordingTranscriptIDs: [transcriptID]
        )
    }
}
