import XCTest
@testable import VoxboardShared

final class LiveTranscriptDraftPreviewTests: XCTestCase {
    func testRenderPlacesLiveSpeechInsideEmptyDraft() {
        var preview = LiveTranscriptDraftPreview()

        let draft = preview.render(
            finalizedText: "Hello",
            volatileText: "world",
            in: ""
        )

        XCTAssertEqual(draft, "Hello world")
    }

    func testRenderAppendsToExistingDraftWithSpace() {
        var preview = LiveTranscriptDraftPreview()

        let draft = preview.render(
            finalizedText: "Spoken text",
            volatileText: nil,
            in: "Typed note"
        )

        XCTAssertEqual(draft, "Typed note Spoken text")
    }

    func testLaterVolatileResultReplacesEarlierPreview() {
        var preview = LiveTranscriptDraftPreview()
        let first = preview.render(
            finalizedText: "",
            volatileText: "A rough phrase",
            in: "Typed note"
        )

        let revised = preview.render(
            finalizedText: "A corrected",
            volatileText: "phrase",
            in: first
        )

        XCTAssertEqual(revised, "Typed note A corrected phrase")
    }

    func testRenderPreservesTypingAddedBeforePreview() {
        var preview = LiveTranscriptDraftPreview()
        let first = preview.render(
            finalizedText: "Live words",
            volatileText: nil,
            in: "Typed"
        )
        let edited = first.replacingOccurrences(of: "Typed", with: "Typed more")

        let revised = preview.render(
            finalizedText: "Live words continue",
            volatileText: nil,
            in: edited
        )

        XCTAssertEqual(revised, "Typed more Live words continue")
    }

    func testCommitReplacesPreviewWithoutDuplicatingTranscript() {
        var preview = LiveTranscriptDraftPreview()
        let liveDraft = preview.render(
            finalizedText: "Hello",
            volatileText: "world",
            in: "Typed note"
        )

        let committed = preview.commit("Hello world.", in: liveDraft)

        XCTAssertEqual(committed, "Typed note Hello world.")
        XCTAssertFalse(preview.isRendering)
    }

    func testCancelRemovesOnlyLivePreview() {
        var preview = LiveTranscriptDraftPreview()
        let liveDraft = preview.render(
            finalizedText: "Temporary speech",
            volatileText: nil,
            in: "Keep this"
        )

        let cancelled = preview.cancel(in: liveDraft)

        XCTAssertEqual(cancelled, "Keep this")
        XCTAssertFalse(preview.isRendering)
    }

    func testRenderAfterTrailingNewlineAddsNoSeparator() {
        var preview = LiveTranscriptDraftPreview()

        let draft = preview.render(finalizedText: "Spoken", volatileText: nil, in: "Line\n")

        XCTAssertEqual(draft, "Line\nSpoken")
    }

    func testRenderInsertsAtCursorBetweenWords() {
        let text = "Hello world"
        var preview = LiveTranscriptDraftPreview(insertionOffset: 5)

        let first = preview.render(finalizedText: "", volatileText: "big", in: text)
        XCTAssertEqual(first, "Hello big world")
        XCTAssertEqual(preview.caretOffset, 9)

        let revised = preview.render(finalizedText: "big", volatileText: "wide", in: first)
        XCTAssertEqual(revised, "Hello big wide world")

        let committed = preview.commit("Big, wide", in: revised)
        XCTAssertEqual(committed, "Hello Big, wide world")
        XCTAssertEqual(preview.caretOffset, 15)
    }

    func testRenderAtCursorBeforePunctuationAddsNoTrailingSpace() {
        var preview = LiveTranscriptDraftPreview(insertionOffset: 5)

        let draft = preview.render(finalizedText: "there", volatileText: nil, in: "Hello.")

        XCTAssertEqual(draft, "Hello there.")
    }

    func testRenderAtStartOfLineAddsNoLeadingSpace() {
        var preview = LiveTranscriptDraftPreview(insertionOffset: 6)

        let draft = preview.render(finalizedText: "Spoken", volatileText: nil, in: "Hello\n\nNext")

        XCTAssertEqual(draft, "Hello\nSpoken\nNext")
    }

    func testTypingBeforeCursorSpanKeepsSpanInPlace() {
        var preview = LiveTranscriptDraftPreview(insertionOffset: 5)
        let first = preview.render(finalizedText: "big", volatileText: nil, in: "Hello world")
        let edited = "Oh, " + first

        let revised = preview.render(finalizedText: "big bright", volatileText: nil, in: edited)

        XCTAssertEqual(revised, "Oh, Hello big bright world")
    }

    func testCancelAtCursorRestoresOriginalText() {
        var preview = LiveTranscriptDraftPreview(insertionOffset: 5)
        let live = preview.render(finalizedText: "big", volatileText: nil, in: "Hello world")

        XCTAssertEqual(preview.cancel(in: live), "Hello world")
    }

    func testInsertLineGoesAheadOfLiveSpan() {
        var preview = LiveTranscriptDraftPreview()
        let live = preview.render(finalizedText: "Talking", volatileText: nil, in: "Note")

        let withTask = preview.insertLine("- [ ] ", in: live)
        XCTAssertEqual(withTask, "Note\n- [ ] \nTalking")

        let revised = preview.render(finalizedText: "Talking more", volatileText: nil, in: withTask)
        XCTAssertEqual(revised, "Note\n- [ ] \nTalking more")
    }

    func testOneShotInsertionUsesCursor() {
        let result = LiveTranscriptDraftPreview.inserting("big", into: "Hello world", atUTF16Offset: 5)

        XCTAssertEqual(result.text, "Hello big world")
        XCTAssertEqual(result.caretOffset, 9)
    }

    func testTypingAfterSpeechFreezesWordsAndNextSpeechFollowsCursor() {
        var preview = LiveTranscriptDraftPreview()
        var draft = preview.render(finalizedText: "Hello there", volatileText: nil, in: "")
        XCTAssertEqual(draft, "Hello there")

        // The writer types after the spoken words; the caret ends past them.
        draft += " typed."
        preview.moveInsertion(toUTF16Offset: (draft as NSString).length, in: draft)

        draft = preview.render(finalizedText: "Hello there", volatileText: "and more", in: draft)
        XCTAssertEqual(draft, "Hello there typed. and more")

        draft = preview.commit("Hello there and more words", in: draft)
        XCTAssertEqual(draft, "Hello there typed. and more words")
    }

    func testMovingCursorEarlierSendsNextSpeechThere() {
        var preview = LiveTranscriptDraftPreview()
        var draft = preview.render(finalizedText: "First", volatileText: nil, in: "Intro. Outro")
        XCTAssertEqual(draft, "Intro. Outro First")

        preview.moveInsertion(toUTF16Offset: 6, in: draft)
        XCTAssertEqual(preview.caretOffset, 6)

        draft = preview.render(finalizedText: "First second", volatileText: nil, in: draft)
        XCTAssertEqual(draft, "Intro. second Outro First")
        XCTAssertEqual(preview.caretOffset, 13)
    }

    func testCancelAfterFreezeKeepsFrozenWords() {
        var preview = LiveTranscriptDraftPreview()
        var draft = preview.render(finalizedText: "Kept", volatileText: nil, in: "")
        preview.moveInsertion(toUTF16Offset: (draft as NSString).length, in: draft)
        draft = preview.render(finalizedText: "Kept dropped", volatileText: nil, in: draft)
        XCTAssertEqual(draft, "Kept dropped")

        XCTAssertEqual(preview.cancel(in: draft), "Kept")
    }
}
