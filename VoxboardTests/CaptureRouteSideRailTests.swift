import SwiftUI
import VoxboardShared
import XCTest
@testable import Voxboard

@MainActor
final class CaptureRouteSideRailTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "CaptureRouteSideRailTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testRailIsOffByDefault() {
        XCTAssertEqual(CaptureRouteRailPlacement.resolve(from: makeDefaults()), .off)
    }

    func testLegacyExpandedRailComesBackOnItsSide() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "capture.presets.quickAccess.railExpanded.v1")
        XCTAssertEqual(CaptureRouteRailPlacement.resolve(from: defaults), .left)
        defaults.set("right", forKey: "capture.presets.quickAccess.railSide.v1")
        XCTAssertEqual(CaptureRouteRailPlacement.resolve(from: defaults), .right)
    }

    func testLegacyCollapsedRailStaysOff() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "capture.presets.quickAccess.railExpanded.v1")
        defaults.set("right", forKey: "capture.presets.quickAccess.railSide.v1")
        XCTAssertEqual(CaptureRouteRailPlacement.resolve(from: defaults), .off)
    }

    func testExplicitChoicePersistsAndBeatsLegacyKeys() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "capture.presets.quickAccess.railExpanded.v1")
        let preferences = CaptureToolbarPreferences(defaults: defaults)
        XCTAssertEqual(preferences.routeRailPlacement, .left)

        preferences.setRouteRailPlacement(.off)
        XCTAssertEqual(defaults.string(forKey: CapturePreferenceKeys.routeSideRail), "off")
        XCTAssertEqual(CaptureToolbarPreferences(defaults: defaults).routeRailPlacement, .off)

        preferences.setRouteRailPlacement(.right)
        XCTAssertEqual(CaptureToolbarPreferences(defaults: defaults).routeRailPlacement, .right)
    }

    func testPhysicalEdgeMapsAroundLayoutDirection() {
        XCTAssertEqual(CaptureRouteRailPlacement.left.overlayAlignment(for: .leftToRight), .bottomLeading)
        XCTAssertEqual(CaptureRouteRailPlacement.right.overlayAlignment(for: .leftToRight), .bottomTrailing)
        XCTAssertEqual(CaptureRouteRailPlacement.left.overlayAlignment(for: .rightToLeft), .bottomTrailing)
        XCTAssertEqual(CaptureRouteRailPlacement.right.overlayAlignment(for: .rightToLeft), .bottomLeading)
    }

    func testActivateSelectsOnlyAnotherEnabledRouteWhileEnabled() {
        var selected: [String] = []
        let profiles = [
            CapturePresetProfile(id: "inbox", name: "Inbox", symbolName: "tray"),
            CapturePresetProfile(id: "work", name: "Work", symbolName: "briefcase"),
            CapturePresetProfile(id: "off", name: "Off", symbolName: "moon", isEnabled: false),
        ]
        let rail = CaptureRouteSideRail(profiles: profiles, selectedID: "inbox", isEnabled: true) {
            selected.append($0)
        }
        XCTAssertFalse(rail.activate(id: "inbox"), "Current route is a no-op")
        XCTAssertFalse(rail.activate(id: "off"))
        XCTAssertFalse(rail.activate(id: "missing"))
        XCTAssertTrue(rail.activate(id: "work"))
        XCTAssertEqual(selected, ["work"])

        let busy = CaptureRouteSideRail(profiles: profiles, selectedID: "inbox", isEnabled: false) {
            selected.append($0)
        }
        XCTAssertFalse(busy.activate(id: "work"))
        XCTAssertEqual(selected, ["work"])
    }
}
