import VoxboardShared
import XCTest
@testable import Voxboard

/// Per-route quick-action pins kept by `CaptureToolbarPreferences` and mirrored
/// to the App Group as `CaptureQuickActionPins`.
@MainActor
final class CaptureToolbarRoutePinsTests: XCTestCase {
    func testUncustomizedRouteFollowsGlobalDefaultRow() throws {
        let (preferences, _) = try makePreferences()

        XCTAssertFalse(preferences.hasCustomPins(forRoute: "tasks"))
        XCTAssertEqual(preferences.pinnedActions(forRoute: "tasks"), preferences.visibleActions)
        XCTAssertEqual(preferences.pinnedActions(forRoute: nil), preferences.visibleActions)
    }

    func testSetPinnedActionsDeduplicatesAndOnlyAffectsThatRoute() throws {
        let (preferences, _) = try makePreferences()

        preferences.setPinnedActions([.checklist, .dueDate, .checklist, .tag], forRoute: "tasks")

        XCTAssertTrue(preferences.hasCustomPins(forRoute: "tasks"))
        XCTAssertEqual(preferences.pinnedActions(forRoute: "tasks"), [.checklist, .dueDate, .tag])
        XCTAssertEqual(preferences.pinnedActions(forRoute: "journal"), preferences.visibleActions)
    }

    func testPinUnpinAndMoveEditTheRouteRow() throws {
        let (preferences, _) = try makePreferences()
        preferences.setPinnedActions([.checklist, .tag], forRoute: "tasks")

        preferences.pin(.timestamp, forRoute: "tasks")
        preferences.pin(.timestamp, forRoute: "tasks")
        XCTAssertEqual(preferences.pinnedActions(forRoute: "tasks"), [.checklist, .tag, .timestamp])

        preferences.movePinnedActions(from: IndexSet(integer: 2), to: 0, forRoute: "tasks")
        XCTAssertEqual(preferences.pinnedActions(forRoute: "tasks"), [.timestamp, .checklist, .tag])

        preferences.unpin(.checklist, forRoute: "tasks")
        XCTAssertEqual(preferences.pinnedActions(forRoute: "tasks"), [.timestamp, .tag])
        XCTAssertFalse(preferences.isPinned(.checklist, forRoute: "tasks"))
        XCTAssertTrue(preferences.unpinnedActions(forRoute: "tasks").contains(.checklist))
        XCTAssertFalse(preferences.unpinnedActions(forRoute: "tasks").contains(.tag))
    }

    func testPinningOnUncustomizedRouteCopiesDefaultRowFirst() throws {
        let (preferences, _) = try makePreferences()
        preferences.setVisible(false, for: .sketch)
        let defaultRow = preferences.visibleActions

        preferences.pin(.sketch, forRoute: "inbox")

        XCTAssertEqual(preferences.pinnedActions(forRoute: "inbox"), defaultRow + [.sketch])
    }

    func testResetPinsRestoresDefaultRow() throws {
        let (preferences, _) = try makePreferences()
        preferences.setPinnedActions([.bold], forRoute: "tasks")

        preferences.resetPins(forRoute: "tasks")

        XCTAssertFalse(preferences.hasCustomPins(forRoute: "tasks"))
        XCTAssertEqual(preferences.pinnedActions(forRoute: "tasks"), preferences.visibleActions)
    }

    func testRoutePinsAndSyncFlagPersistToSharedPinsAndReload() throws {
        let (preferences, defaults) = try makePreferences()
        preferences.setPinnedActions([.checklist, .dueDate], forRoute: "tasks")
        preferences.setSyncsQuickActionsAcrossSurfaces(false)

        let shared = CaptureQuickActionPins.load(from: defaults)
        XCTAssertEqual(shared.routePins["tasks"], [.checklist, .dueDate])
        XCTAssertEqual(shared.defaultPins, preferences.visibleActions)
        XCTAssertFalse(shared.syncsAcrossSurfaces)

        let reloaded = CaptureToolbarPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.pinnedActions(forRoute: "tasks"), [.checklist, .dueDate])
        XCTAssertFalse(reloaded.syncsQuickActionsAcrossSurfaces)
    }

    func testReloadSharedPinsPicksUpChangesFromAnotherProcess() throws {
        let (preferences, defaults) = try makePreferences()
        XCTAssertFalse(preferences.hasCustomPins(forRoute: "journal"))

        // Another process (keyboard, Mac) writes pins directly.
        CaptureQuickActionPins(
            defaultPins: [.checklist],
            routePins: ["journal": [.date, .currentLocation]],
            syncsAcrossSurfaces: false
        ).save(to: defaults)
        preferences.reloadSharedPins()

        XCTAssertEqual(preferences.pinnedActions(forRoute: "journal"), [.date, .currentLocation])
        XCTAssertFalse(preferences.syncsQuickActionsAcrossSurfaces)
    }

    func testTimestampFormatIsMirroredToSeparatePinDefaults() throws {
        let (defaults, _) = try makeDefaults()
        let (pinDefaults, _) = try makeDefaults()
        let preferences = CaptureToolbarPreferences(defaults: defaults, pinDefaults: pinDefaults)
        XCTAssertEqual(CaptureQuickActionPins.sharedTimestampFormat(from: pinDefaults), .twelveHour)

        preferences.setTimestampFormat(.twentyFourHour)

        XCTAssertEqual(CaptureQuickActionPins.sharedTimestampFormat(from: pinDefaults), .twentyFourHour)
    }

    private func makePreferences() throws -> (CaptureToolbarPreferences, UserDefaults) {
        let (defaults, _) = try makeDefaults()
        return (CaptureToolbarPreferences(defaults: defaults), defaults)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "CaptureToolbarRoutePinsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return (defaults, suiteName)
    }
}
