import XCTest
import VoxboardShared
@testable import Voxboard

@MainActor
final class URLDeliveryHeadersDraftTests: XCTestCase {
    func testEmptyDraftStartsWithOneBlankRow() throws {
        let draft = URLDeliveryHeadersDraft()
        XCTAssertEqual(draft.rows.count, 1)
        XCTAssertTrue(draft.rows[0].isBlank)
        XCTAssertEqual(try draft.validatedHeaders(), [:])
        XCTAssertFalse(draft.hasUnsavedChanges(comparedTo: [:]))
    }

    func testStoredHeadersLoadSortedAndRoundTripWithoutSplittingValues() throws {
        let headers = ["X-Zebra": "https://example.invalid:8443/path", "X-Alpha": "one: two"]
        let draft = URLDeliveryHeadersDraft(headers: headers)
        XCTAssertEqual(draft.rows.map(\.name), ["X-Alpha", "X-Zebra"])
        XCTAssertEqual(try draft.validatedHeaders(), headers)
        XCTAssertFalse(draft.hasUnsavedChanges(comparedTo: headers))
    }

    func testAddAndRemovePreserveOtherRowIdentityAndValues() throws {
        var draft = URLDeliveryHeadersDraft(headers: ["X-First": "first", "X-Second": "second"])
        let retained = draft.rows[1]
        let addedID = draft.addRow()
        XCTAssertEqual(Set(draft.rows.map(\.id)).count, 3)
        draft.removeRow(id: draft.rows[0].id)
        XCTAssertEqual(draft.rows[0], retained)
        XCTAssertEqual(draft.rows[1].id, addedID)
        XCTAssertEqual(try draft.validatedHeaders(), ["X-Second": "second"])
    }

    func testDeletingLastHeaderLeavesEmptyInputAndClearsSavedHeadersOnSave() throws {
        let saved = ["X-Api-Key": "synthetic-value"]
        var draft = URLDeliveryHeadersDraft(headers: saved)
        draft.removeRow(id: draft.rows[0].id)
        XCTAssertEqual(draft.rows.count, 1)
        XCTAssertTrue(draft.rows[0].isBlank)
        XCTAssertEqual(try draft.validatedHeaders(), [:])
        XCTAssertTrue(draft.hasUnsavedChanges(comparedTo: saved))
    }

    func testWhitespaceOnlyRowsAreIgnoredAndFieldEdgesAreTrimmed() throws {
        var draft = URLDeliveryHeadersDraft()
        draft.rows[0].name = " X-Example "
        draft.rows[0].value = " hello: world "
        draft.rows.append(.init(name: " ", value: " "))
        XCTAssertEqual(try draft.validatedHeaders(), ["X-Example": "hello: world"])
    }

    func testNamedHeaderMayHaveAnEmptyValue() throws {
        let draft = URLDeliveryHeadersDraft(headers: ["X-Empty": ""])
        XCTAssertEqual(try draft.validatedHeaders(), ["X-Empty": ""])
    }

    func testValueWithoutHeaderNameFailsInsteadOfBeingDiscarded() {
        var draft = URLDeliveryHeadersDraft()
        draft.rows[0].value = "synthetic-value"
        assertInvalid(draft)
    }

    func testCaseInsensitiveDuplicateHeadersFailInsteadOfOverwriting() {
        var draft = URLDeliveryHeadersDraft()
        draft.rows = [.init(name: "X-Api-Key", value: "first"), .init(name: "x-api-key", value: "second")]
        assertInvalid(draft)
    }

    func testPastedNewlinesAndInvalidNamesFailValidation() {
        for row in [
            URLDeliveryHeadersDraft.Row(name: "X-Test", value: "ok\r\nInjected: no"),
            .init(name: "X-Test", value: "ok\n"),
            .init(name: "X-Test\r", value: "ok"),
            .init(name: "Bad Name", value: "ok"),
            .init(name: "Bad:Name", value: "ok")
        ] {
            var draft = URLDeliveryHeadersDraft()
            draft.rows = [row]
            assertInvalid(draft)
        }
    }

    func testForbiddenTransportHeadersStillFail() {
        for name in ["Host", "Cookie", "Connection", "Content-Length"] {
            assertInvalid(URLDeliveryHeadersDraft(headers: [name: "synthetic-value"]))
        }
    }

    func testExistingHeaderCountAndSizeLimitsStillApply() {
        var draft = URLDeliveryHeadersDraft()
        draft.rows = (0..<33).map { .init(name: "X-\($0)", value: "ok") }
        assertInvalid(draft)
        assertInvalid(URLDeliveryHeadersDraft(headers: ["X-Large": String(repeating: "a", count: 16 * 1024)]))
    }

    func testDirtyStateTracksEditsAndRemovalButNotBlankPlaceholdersOrRowIDs() throws {
        let saved = ["X-Test": "saved"]
        var draft = URLDeliveryHeadersDraft(headers: saved)
        draft.addRow()
        XCTAssertFalse(draft.hasUnsavedChanges(comparedTo: saved))
        draft.rows[0].value = "edited"
        XCTAssertTrue(draft.hasUnsavedChanges(comparedTo: saved))
        let updated = try draft.validatedHeaders()
        XCTAssertFalse(draft.hasUnsavedChanges(comparedTo: updated))
        XCTAssertFalse(URLDeliveryHeadersDraft(headers: updated).hasUnsavedChanges(comparedTo: updated))
    }

    private func assertInvalid(_ draft: URLDeliveryHeadersDraft, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try draft.validatedHeaders(), file: file, line: line) {
            XCTAssertEqual($0 as? URLDeliveryValidationError, .invalidHeaders, file: file, line: line)
        }
        XCTAssertTrue(draft.hasUnsavedChanges(comparedTo: [:]), file: file, line: line)
    }
}
