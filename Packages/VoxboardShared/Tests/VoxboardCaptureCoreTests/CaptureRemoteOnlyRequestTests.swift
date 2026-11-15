import XCTest
@testable import VoxboardCaptureCore

final class CaptureRemoteOnlyRequestTests: XCTestCase {
    func test_remoteOnlyRequestNeedsNoDestination() throws {
        let draft = CaptureDraft(text: "Synthetic remote thought")

        let request = try draft.makeRequest(source: .app, remoteOnly: true)

        XCTAssertEqual(request.id, draft.requestID)
        XCTAssertEqual(request.destinationID, CaptureRequest.remoteOnlyDestinationID)
        XCTAssertTrue(request.isRemoteOnly)
        XCTAssertEqual(request.payloads, [.text("Synthetic remote thought")])
    }

    func test_remoteOnlyRequestNeverCarriesAVaultDestination() throws {
        let draft = CaptureDraft(text: "Synthetic", destinationID: UUID())

        let request = try draft.makeRequest(source: .app, resolvedDestinationID: UUID(), remoteOnly: true)

        XCTAssertTrue(request.isRemoteOnly)
    }

    func test_localRequestStillRequiresDestination() throws {
        let draft = CaptureDraft(text: "Synthetic local thought")

        XCTAssertThrowsError(try draft.makeRequest(source: .app)) { error in
            XCTAssertEqual(error as? CaptureDraftError, .destinationRequired)
        }
        let destinationID = UUID()
        let request = try draft.makeRequest(source: .app, resolvedDestinationID: destinationID)
        XCTAssertEqual(request.destinationID, destinationID)
        XCTAssertFalse(request.isRemoteOnly)
    }
}
