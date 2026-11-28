import Foundation
import Testing
import VoxboardShared
@testable import Voxboard

/// Issue #204: when the first save binds the composer to the whole file (after
/// "Finding Location…" on a Preset with location), the caret and the scroll
/// position stay on the words just added instead of jumping to the top.
@MainActor
struct LiveNoteBoundCaretTests {
    @Test func caretGoesJustPastTheEntryInTheFile() {
        let file = "---\nlocations:\n  - place: \"Van Ness\"\n---\n\n## Notes\n\n### 15:44\nline one\nline two\n"
        let offset = QuickCaptureViewModel.boundNoteCaretOffset(
            editorText: file,
            fileText: file,
            renderedEntry: "\n### 15:44\nline one\nline two\n"
        )
        #expect(offset == (file as NSString).range(of: "line two").upperBound)
    }

    @Test func caretUsesTheLastMatchAndFallsBackToTheEnd() {
        let file = "## Notes\n\nSame words\n\nSame words\n\nLater"
        #expect(
            QuickCaptureViewModel.boundNoteCaretOffset(
                editorText: file, fileText: file, renderedEntry: "Same words"
            ) == (file as NSString).range(of: "Same words", options: .backwards).upperBound
        )
        #expect(
            QuickCaptureViewModel.boundNoteCaretOffset(
                editorText: file, fileText: file, renderedEntry: "Rewritten by the Preset"
            ) == (file as NSString).length
        )
        #expect(
            QuickCaptureViewModel.boundNoteCaretOffset(
                editorText: file, fileText: file, renderedEntry: nil
            ) == (file as NSString).length
        )
    }

    @Test func wordsTypedDuringTheSaveKeepTheCaretAtTheEnd() {
        let file = "## Notes\n\nFirst entry\n"
        let editor = file + "\nTyped while saving"
        #expect(
            QuickCaptureViewModel.boundNoteCaretOffset(
                editorText: editor, fileText: file, renderedEntry: "First entry"
            ) == (editor as NSString).length
        )
    }

    /// The real first save into a daily note that already holds earlier
    /// entries: the caret request points at the new words, not at the old
    /// draft offset (which lands in the earlier entries).
    @Test func firstSaveIntoAnExistingNotePlacesTheCaretAfterTheNewWords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent("Daily"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let earlier = (1...30).map { "- earlier entry \($0)" }.joined(separator: "\n")
        let destination = CaptureDestination(
            name: "Daily", rootBookmark: try vault.bookmarkData(), rootName: "Vault",
            noteTarget: .existingNote(relativePath: "Daily/Log.md")
        )
        try "---\ntags: [log]\n---\n\n## Log\n\n\(earlier)\n".write(
            to: vault.appendingPathComponent("Daily/Log.md"), atomically: true, encoding: .utf8
        )
        try await CaptureLibraryStore(fileURL: root.appendingPathComponent(AppConstants.captureLibraryFilename))
            .save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))
        let suite = "LiveNoteBoundCaret-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = QuickCaptureViewModel(
            captureRootURL: root, defaults: defaults, pipeline: CapturePipeline(),
            hasPaidCaptureAccess: { true }
        )
        model.liveNotesEnabled = true
        await model.load()

        let words = "Radiator visit Tuesday"
        model.draft.text = words
        await model.submit()

        #expect(model.liveNote != nil, "the first save binds the composer to the file")
        let caret = try #require(model.liveNoteBoundCaret)
        let text = model.draft.text as NSString
        #expect(text.length > (words as NSString).length, "the composer now holds the whole file")
        #expect(caret.utf16Offset == text.range(of: words, options: .backwards).upperBound)
    }

    /// A caret moved from outside (the binding above) is scrolled into view
    /// even while the writer is typing and the caret is not at the end; before
    /// #204 the editor kept whatever offset UIKit left after the new text.
    @Test func editorFollowsACaretMovedFromOutside() {
        #expect(MarkdownComposerTextView.followsSelection(
            textChanged: true, selectionChanged: true, selectionEnd: 40, textEnd: 900, isFirstResponder: true
        ))
        #expect(MarkdownComposerTextView.followsSelection(
            textChanged: false, selectionChanged: true, selectionEnd: 40, textEnd: 900, isFirstResponder: true
        ))
    }

    /// Unchanged: speech landing elsewhere never steals the typing writer's
    /// view, and text that ends at the caret is followed.
    @Test func editorKeepsTheWritersViewForTextAlone() {
        #expect(!MarkdownComposerTextView.followsSelection(
            textChanged: true, selectionChanged: false, selectionEnd: 40, textEnd: 900, isFirstResponder: true
        ))
        #expect(MarkdownComposerTextView.followsSelection(
            textChanged: true, selectionChanged: false, selectionEnd: 900, textEnd: 900, isFirstResponder: true
        ))
        #expect(MarkdownComposerTextView.followsSelection(
            textChanged: true, selectionChanged: false, selectionEnd: 40, textEnd: 900, isFirstResponder: false
        ))
        #expect(!MarkdownComposerTextView.followsSelection(
            textChanged: false, selectionChanged: false, selectionEnd: 40, textEnd: 900, isFirstResponder: false
        ))
    }
}
