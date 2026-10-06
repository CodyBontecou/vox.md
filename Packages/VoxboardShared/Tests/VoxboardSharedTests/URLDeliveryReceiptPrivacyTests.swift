import XCTest
@testable import VoxboardShared

final class URLDeliveryReceiptPrivacyTests: XCTestCase {
    func testLegacyFullURLMetadataStripsCredentialsPathQueryAndFragment() {
        let receipt = makeReceipt("https://synthetic-user:synthetic-secret@example.invalid:9443/PRIVATE-PATH?private=PRIVATE-QUERY#PRIVATE-FRAGMENT")
        XCTAssertEqual(receipt.origin, "https://example.invalid:9443")
    }

    func testMalformedOrNonHTTPLegacyURLHasNoDisplayableOrigin() {
        for url in ["not a URL", "file:///PRIVATE-PATH", "javascript://example.invalid/PRIVATE-PATH", "https:///PRIVATE-PATH"] {
            XCTAssertNil(makeReceipt(url).origin)
        }
    }

    private func makeReceipt(_ url: String) -> URLDeliveryReceipt {
        URLDeliveryReceipt(id: UUID().uuidString, urlString: url, attempt: 1, outcome: .unknownOutcome,
                           statusCode: nil, message: "Synthetic", date: Date())
    }
}
