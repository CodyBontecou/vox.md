import Foundation
import Testing
import VoxboardShared
@testable import Voxboard

/// Quick Capture from the lock screen / Control Center (issue #85): with Live
/// Notes on, the launch opens a blank capture in the preset, the way it did
/// before Live Notes, instead of the file that was left open. Appending every
/// capture to one ongoing note is the preset's job (rolling or existing-note
/// destination), not a separate setting.
@MainActor
struct QuickCaptureLiveNoteLaunchTests {
    private struct Fixture {
        let root: URL
        let vault: URL
        let defaults: UserDefaults
        let suite: String
        let destination: CaptureDestination
        let model: QuickCaptureViewModel

        func tearDown() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeFixture(noteTarget: CaptureNoteTarget) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent("Inbox"), withIntermediateDirectories: true
        )
        try "# Earlier note\n".write(
            to: vault.appendingPathComponent("Inbox/Earlier.md"), atomically: true, encoding: .utf8
        )
        let destination = CaptureDestination(
            name: "Inbox", rootBookmark: try vault.bookmarkData(), rootName: "Vault",
            noteTarget: noteTarget
        )
        try await CaptureLibraryStore(fileURL: root.appendingPathComponent(AppConstants.captureLibraryFilename))
            .save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))
        let suite = "QuickCaptureLiveNote-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let model = QuickCaptureViewModel(captureRootURL: root, defaults: defaults, pipeline: CapturePipeline())
        model.liveNotesEnabled = true
        await model.load()
        return Fixture(
            root: root, vault: vault, defaults: defaults, suite: suite,
            destination: destination, model: model
        )
    }

    private func openEarlierNote(_ fixture: Fixture) async throws {
        await fixture.model.openLiveNote(binding: LiveNoteBinding(
            destinationID: fixture.destination.id,
            relativePath: "Inbox/Earlier.md",
            savedVersion: VaultNoteVersion(sha256: ""),
            entryRequestID: nil,
            presetID: nil
        ))
        #expect(fixture.model.liveNote?.binding.relativePath == "Inbox/Earlier.md")
    }

    /// Opens Quick Capture, types a thought and saves it; returns the file it landed in.
    private func quickCapture(_ text: String, in fixture: Fixture) async throws -> String {
        let model = fixture.model
        await model.handleDeepLink(.openComposer(CaptureDeepLinkDraft(source: .widget)))
        #expect(model.liveNote == nil, "Quick Capture starts on a blank note")
        #expect(model.draft.text.isEmpty)
        #expect(model.draft.captureSource == .widget)
        model.draft.text = text
        await model.submit()
        return try #require(model.liveNote?.binding.relativePath)
    }

    @Test func defaultQuickCaptureLeavesTheOpenNoteAndStartsBlank() async throws {
        let fixture = try await makeFixture(noteTarget: .newNote(pathTemplate: "Inbox/{title}.md"))
        defer { fixture.tearDown() }
        try await openEarlierNote(fixture)

        let first = try await quickCapture("Buy radiator valves", in: fixture)
        let second = try await quickCapture("Call the landlord", in: fixture)

        #expect(first != "Inbox/Earlier.md")
        #expect(second != first, "each lock-screen capture is its own note by default")
        #expect(
            try String(contentsOf: fixture.vault.appendingPathComponent("Inbox/Earlier.md"), encoding: .utf8)
                == "# Earlier note\n",
            "the note that was open is left untouched"
        )
        #expect(fixture.model.lastClosedNote?.binding.relativePath == first, "Reopen still offers the closed note")
    }

    @Test func rollingPresetAppendsEveryQuickCaptureToOneNote() async throws {
        let fixture = try await makeFixture(
            noteTarget: .rollingNote(pathTemplate: "Inbox/Rolling {date}.md", period: .daily)
        )
        defer { fixture.tearDown() }
        try await openEarlierNote(fixture)

        let first = try await quickCapture("Buy radiator valves", in: fixture)
        let second = try await quickCapture("Call the landlord", in: fixture)

        #expect(first.hasPrefix("Inbox/Rolling "))
        #expect(second == first, "a rolling preset keeps adding to the same note")
        let contents = try String(contentsOf: fixture.vault.appendingPathComponent(first), encoding: .utf8)
        #expect(contents.contains("Buy radiator valves"))
        #expect(contents.contains("Call the landlord"))
    }

    @Test func onlyWidgetLaunchesCloseAnOpenNote() {
        #expect(QuickCaptureViewModel.quickCaptureStartsBlankNote(source: .widget, liveNoteIsOpen: true))
        #expect(!QuickCaptureViewModel.quickCaptureStartsBlankNote(source: .widget, liveNoteIsOpen: false))
        #expect(!QuickCaptureViewModel.quickCaptureStartsBlankNote(source: .deepLink, liveNoteIsOpen: true))
        #expect(!QuickCaptureViewModel.quickCaptureStartsBlankNote(source: .shortcut, liveNoteIsOpen: true))
        #expect(!QuickCaptureViewModel.quickCaptureStartsBlankNote(source: nil, liveNoteIsOpen: true))
    }
}
