import VoxboardShared
import XCTest
@testable import Voxboard

/// Record new note: one tap from an open note closes it like New note and
/// leaves a blank composer for the existing Speak recording path.
@MainActor
final class RecordNewNoteActionTests: XCTestCase {
    private var root: URL!
    private var vault: URL!
    private var destination: CaptureDestination!
    private var suite: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        vault = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Inbox"), withIntermediateDirectories: true)
        try "# Meeting\nAgenda\n".write(to: vault.appendingPathComponent("Inbox/Meeting.md"), atomically: true, encoding: .utf8)
        destination = CaptureDestination(
            name: "Inbox", rootBookmark: try vault.bookmarkData(), rootName: "Vault",
            noteTarget: .newNote(pathTemplate: "Inbox/{title}.md")
        )
        try await CaptureLibraryStore(fileURL: root.appendingPathComponent(AppConstants.captureLibraryFilename))
            .save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))
        suite = "RecordNewNote." + UUID().uuidString
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel(liveNotes: Bool = true) async throws -> QuickCaptureViewModel {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let model = QuickCaptureViewModel(captureRootURL: root, defaults: defaults, pipeline: CapturePipeline())
        model.liveNotesEnabled = liveNotes
        await model.load()
        return model
    }

    private func openMeetingNote(in model: QuickCaptureViewModel) async {
        await model.openLiveNote(binding: LiveNoteBinding(
            destinationID: destination.id, relativePath: "Inbox/Meeting.md",
            savedVersion: VaultNoteVersion(sha256: ""), entryRequestID: nil, presetID: nil
        ))
    }

    func testFromAnOpenNoteItClosesTheFileAndLeavesABlankNoteToRecordInto() async throws {
        let model = try await makeModel()
        await openMeetingNote(in: model)
        XCTAssertNotNil(model.liveNote)
        XCTAssertTrue(model.canRecordNewNote)
        let presetID = model.draft.voxID
        let closedDraftID = model.draft.id

        let ready = await model.prepareNewNoteForRecording()

        XCTAssertTrue(ready)
        XCTAssertNil(model.liveNote, "the recording must not go into the note that was open")
        XCTAssertFalse(model.draft.hasCaptureContent)
        XCTAssertNotEqual(model.draft.id, closedDraftID, "a fresh draft receives the recording")
        XCTAssertEqual(model.draft.voxID, presetID, "the preset carries over to the new note")
        XCTAssertEqual(model.lastClosedNote?.binding.relativePath, "Inbox/Meeting.md", "Reopen still offered")
        XCTAssertEqual(model.liveNoteRecordingLine?.isLive, false)
        XCTAssertEqual(
            try String(contentsOf: vault.appendingPathComponent("Inbox/Meeting.md"), encoding: .utf8),
            "# Meeting\nAgenda\n",
            "the closed file is left as it was"
        )
    }

    func testNotOfferedOnABlankNoteWhereSpeakAlreadyRecordsANewNote() async throws {
        let model = try await makeModel()
        XCTAssertFalse(model.canRecordNewNote)

        let ready = await model.prepareNewNoteForRecording()

        XCTAssertFalse(ready)
        XCTAssertNil(model.lastClosedNote)
    }

    func testNotOfferedWithLiveNotesOff() async throws {
        let model = try await makeModel(liveNotes: false)
        model.draft.text = "Unsent words"
        XCTAssertFalse(model.canRecordNewNote)

        let ready = await model.prepareNewNoteForRecording()

        XCTAssertFalse(ready)
        XCTAssertEqual(model.draft.text, "Unsent words", "classic Send-and-clear drafts are never closed")
    }

    func testWhileRecordingIntoTheOpenNoteItKeepsThatNoteAndRecording() async throws {
        let model = try await makeModel()
        await openMeetingNote(in: model)
        model.beginRecordedTranscriptInsertion(atUTF16Offset: nil)
        await model.updateLiveRecordedTranscript(finalizedText: "Action items", volatileText: nil)
        XCTAssertTrue(model.hasLiveRecordedTranscriptPreview)
        XCTAssertFalse(model.canRecordNewNote)

        let ready = await model.prepareNewNoteForRecording()

        XCTAssertFalse(ready)
        XCTAssertEqual(model.liveNote?.binding.relativePath, "Inbox/Meeting.md")
        XCTAssertNil(model.lastClosedNote)
        await model.cancelLiveRecordedTranscript()
    }
}
