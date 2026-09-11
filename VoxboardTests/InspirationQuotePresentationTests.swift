import XCTest
@testable import Voxboard

final class InspirationQuotePresentationTests: XCTestCase {
    func testQuoteStaysVisibleUntilTextIsInserted() {
        XCTAssertTrue(InspirationQuotePresentation.shouldShow(forDraftText: ""))
        XCTAssertFalse(InspirationQuotePresentation.shouldShow(forDraftText: " "))
        XCTAssertFalse(InspirationQuotePresentation.shouldShow(forDraftText: "A"))
    }
}
