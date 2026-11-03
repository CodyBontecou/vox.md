import XCTest
@testable import Voxboard

final class InspirationQuotePresentationTests: XCTestCase {
    func testQuoteStaysVisibleUntilTextIsInserted() {
        XCTAssertTrue(InspirationQuotePresentation.shouldShow(forDraftText: ""))
        XCTAssertFalse(InspirationQuotePresentation.shouldShow(forDraftText: " "))
        XCTAssertFalse(InspirationQuotePresentation.shouldShow(forDraftText: "A"))
    }

    func testQuoteSharesTheEditorWithARoutePromptWhenThereIsRoom() {
        let roomy = InspirationQuotePresentation.minimumEditorHeightBesidePrompt
        XCTAssertTrue(InspirationQuotePresentation.shouldShow(forDraftText: "", hasPrompt: true, editorHeight: roomy))
        XCTAssertTrue(InspirationQuotePresentation.shouldShow(forDraftText: "", hasPrompt: true, editorHeight: 500))
        XCTAssertFalse(InspirationQuotePresentation.shouldShow(forDraftText: "", hasPrompt: true, editorHeight: 140))
    }

    func testQuoteIgnoresEditorHeightWithoutARoutePrompt() {
        XCTAssertTrue(InspirationQuotePresentation.shouldShow(forDraftText: "", hasPrompt: false, editorHeight: 140))
        XCTAssertFalse(InspirationQuotePresentation.shouldShow(forDraftText: "A", hasPrompt: false, editorHeight: 500))
    }
}
