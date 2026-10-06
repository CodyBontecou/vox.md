import XCTest
import VoxboardShared
@testable import Voxboard

@MainActor
final class CaptureInboxLocationPresentationTests: XCTestCase {
    func testReturningToCaptureDoesNotPresentSavedLocationDecision() async throws {
        let f = try await fixture()
        let draft = f.model.draft
        for _ in 0..<3 {
            // App foreground and notification handlers use this same drain.
            await f.model.processPendingInbox()
            XCTAssertEqual(f.model.inboxLocationDecision?.requestID, f.request.id)
            XCTAssertFalse(f.model.isInboxLocationDecisionPresented,
                           "Discovering pending work must not open a dialog on return to Capture")
            XCTAssertEqual(f.model.draft, draft)
            let saved = try await f.inbox.request(requestID: f.request.id, states: [.pending])
            XCTAssertEqual(saved?.payloads, f.request.payloads)
            XCTAssertEqual(saved?.locationOutcome, f.request.locationOutcome)
            XCTAssertNil(saved?.locationDecisionOverride)
            XCTAssertNil(f.model.lastReceipt)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.note.path))
        }
        XCTAssertEqual(f.location.calls, 0, "Recovery must not reacquire a later location")
    }

    func testExplicitReviewCanBeCancelledWithoutSendingAndSurvivesRelaunch() async throws {
        let f = try await fixture()
        await f.model.processPendingInbox()
        f.model.presentInboxLocationDecision()
        XCTAssertTrue(f.model.isInboxLocationDecisionPresented)
        // The native dialog writes false on Cancel or backdrop dismissal.
        f.model.isInboxLocationDecisionPresented = false
        await f.model.processPendingInbox()
        XCTAssertFalse(f.model.isInboxLocationDecisionPresented)
        XCTAssertEqual(f.model.inboxLocationDecision?.requestID, f.request.id)
        let relaunched = QuickCaptureViewModel(captureRootURL: f.root, defaults: f.defaults,
                                               locationProvider: f.location)
        await relaunched.processPendingInbox()
        XCTAssertEqual(relaunched.inboxLocationDecision?.requestID, f.request.id)
        XCTAssertFalse(relaunched.isInboxLocationDecisionPresented)
        let state = try await f.inbox.state(of: f.request.id)
        XCTAssertEqual(state, .pending)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.note.path))
        XCTAssertEqual(f.location.calls, 0)
    }

    func testRefreshDoesNotReplaceTheRequestBeingReviewed() async throws {
        let f = try await fixture()
        await f.model.processPendingInbox()
        f.model.presentInboxLocationDecision()
        let other = try await enqueueEarlierRequest(in: f)
        await f.model.processPendingInbox()
        XCTAssertTrue(f.model.isInboxLocationDecisionPresented)
        XCTAssertEqual(f.model.inboxLocationDecision?.requestID, f.request.id)
        await f.model.discardInboxLocationRequest(expectedRequestID: f.request.id)
        XCTAssertFalse(f.model.isInboxLocationDecisionPresented)
        XCTAssertEqual(f.model.inboxLocationDecision?.requestID, other.id)
        let originalState = try await f.inbox.state(of: f.request.id)
        let otherState = try await f.inbox.state(of: other.id)
        XCTAssertNil(originalState)
        XCTAssertEqual(otherState, .pending)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.note.path))
    }

    func testSendWithoutLocationDeliversOnlyTheExplicitlyReviewedCapture() async throws {
        let f = try await fixture()
        await f.model.processPendingInbox()
        f.model.presentInboxLocationDecision()
        let other = try await enqueueEarlierRequest(in: f)
        await f.model.processPendingInbox()
        await f.model.sendInboxRequestWithoutLocation(expectedRequestID: f.request.id)
        XCTAssertNil(f.model.errorMessage)
        let state = try await f.inbox.state(of: f.request.id)
        let otherState = try await f.inbox.state(of: other.id)
        XCTAssertEqual(state, .completed)
        XCTAssertEqual(otherState, .pending)
        XCTAssertEqual(f.model.inboxLocationDecision?.requestID, other.id)
        XCTAssertFalse(f.model.isInboxLocationDecisionPresented)
        XCTAssertEqual(f.model.draft.text, "Unrelated current draft")
        XCTAssertEqual(f.location.calls, 0)
        let delivered = try String(contentsOf: f.note, encoding: .utf8)
        XCTAssertTrue(delivered.contains("Saved synthetic capture"))
        XCTAssertFalse(delivered.contains("Other synthetic capture"))
    }

    func testStaleDialogActionsNeverSendOrDiscardADifferentCapture() async throws {
        let f = try await fixture()
        await f.model.processPendingInbox()
        let wrongID = UUID()
        await f.model.sendInboxRequestWithoutLocation(expectedRequestID: wrongID)
        await f.model.discardInboxLocationRequest(expectedRequestID: wrongID)
        let state = try await f.inbox.state(of: f.request.id)
        XCTAssertEqual(state, .pending)
        XCTAssertEqual(f.model.inboxLocationDecision?.requestID, f.request.id)
        XCTAssertNil(f.model.lastReceipt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.note.path))
    }

    func testExternalResolutionClearsStaleChoicesWithoutOpeningTheNextCapture() async throws {
        let f = try await fixture()
        await f.model.processPendingInbox()
        f.model.presentInboxLocationDecision()
        let discarded = try await f.inbox.discard(requestID: f.request.id)
        XCTAssertTrue(discarded)
        await f.model.processPendingInbox()
        XCTAssertNil(f.model.inboxLocationDecision)
        XCTAssertFalse(f.model.isInboxLocationDecisionPresented)
        f.model.presentInboxLocationDecision()
        XCTAssertFalse(f.model.isInboxLocationDecisionPresented)
    }

    func testConcurrentRefreshesLeaveTheCapturePendingWithoutPresentation() async throws {
        let f = try await fixture()
        async let first: Void = f.model.processPendingInbox()
        async let second: Void = f.model.processPendingInbox()
        _ = await (first, second)
        XCTAssertEqual(f.model.inboxLocationDecision?.requestID, f.request.id)
        XCTAssertFalse(f.model.isInboxLocationDecisionPresented)
        let state = try await f.inbox.state(of: f.request.id)
        XCTAssertEqual(state, .pending)
        XCTAssertNil(f.model.lastReceipt)
    }

    private func enqueueEarlierRequest(in f: Fixture) async throws -> CaptureRequest {
        let request = CaptureRequest(
            createdAt: Date(timeIntervalSince1970: 50), source: .voice,
            destinationID: f.request.destinationID, payloads: [.text("Other synthetic capture")],
            voxProfile: f.request.voxProfile, locationOutcome: f.request.locationOutcome
        )
        try await f.inbox.enqueue(request)
        return request
    }

    private func fixture() async throws -> Fixture {
        let name = "CaptureInboxLocationPresentationTests-\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        let captureRoot = root.appendingPathComponent("capture", isDirectory: true)
        let vault = root.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: captureRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let destination = CaptureDestination(
            name: "Synthetic Vault", rootBookmark: try vault.bookmarkData(), rootName: "Vault",
            noteTarget: .existingNote(relativePath: "Inbox.md")
        )
        try await CaptureLibraryStore(
            fileURL: captureRoot.appendingPathComponent(AppConstants.captureLibraryFilename)
        ).save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))
        let request = CaptureRequest(
            source: .voice, destinationID: destination.id, payloads: [.text("Saved synthetic capture")],
            voxProfile: CapturePresetProfile(
                id: "default", name: "Default", symbolName: "waveform",
                locationPolicy: CapturePresetLocationPolicy(isEnabled: true, unavailableBehavior: .ask)
            ),
            locationOutcome: .unavailable(.timeout, attemptedAt: Date(timeIntervalSince1970: 100))
        )
        let inbox = CaptureInbox(rootDirectoryURL: captureRoot)
        try await inbox.enqueue(request)
        let location = LocationProbe()
        let model = QuickCaptureViewModel(
            captureRootURL: captureRoot, defaults: defaults,
            pipeline: CapturePipeline(deliveryAccounting: UnmeteredCaptureDeliveryAccounting()),
            locationProvider: location
        )
        model.draft.text = "Unrelated current draft"
        addTeardownBlock { @MainActor in
            _ = await model.flushDraftForTermination()
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: root)
        }
        return Fixture(model: model, inbox: inbox, request: request, location: location,
                       note: vault.appendingPathComponent("Inbox.md"), root: captureRoot, defaults: defaults)
    }

    private struct Fixture {
        let model: QuickCaptureViewModel
        let inbox: CaptureInbox
        let request: CaptureRequest
        let location: LocationProbe
        let note: URL
        let root: URL
        let defaults: UserDefaults
    }

    private final class LocationProbe: CaptureLocationOutcomeProviding {
        var calls = 0
        func resolveLocation(policy: CapturePresetLocationPolicy, source: CaptureSource) async -> CaptureLocationOutcome {
            calls += 1
            return .unavailable(.timeout, attemptedAt: Date(timeIntervalSince1970: 100))
        }
    }
}
