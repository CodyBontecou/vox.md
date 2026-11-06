import XCTest

final class WatchRouteSummaryPayloadTests: XCTestCase {
    func testLegacySummaryWithoutRouteFieldsDecodesWithFallbacks() {
        let context: [String: Any] = [
            WatchRecordingPayloadKey.phase: "idle",
            WatchRecordingPayloadKey.presetSummaries: [
                [
                    WatchRecordingPayloadKey.selectedPresetID: "meetings",
                    WatchRecordingPayloadKey.selectedPresetName: "Meetings",
                    WatchRecordingPayloadKey.presetSymbolName: "person.2",
                ],
                [
                    WatchRecordingPayloadKey.selectedPresetID: "inbox",
                    WatchRecordingPayloadKey.selectedPresetName: "Inbox",
                ],
                [
                    WatchRecordingPayloadKey.selectedPresetID: "tasks",
                    WatchRecordingPayloadKey.selectedPresetName: "Tasks",
                ],
                [
                    WatchRecordingPayloadKey.selectedPresetID: "icon",
                    WatchRecordingPayloadKey.selectedPresetName: "Icon-only Route",
                    WatchRecordingPayloadKey.presetVisibleName: "",
                ],
            ],
        ]

        let routes = WatchRecordingSnapshot(dictionary: context).availablePresets
        XCTAssertEqual(routes.map(\.initial), ["M", "I", "T", ""])
        XCTAssertEqual(routes.map(\.tileStyle), [.accent, .light, .graphite, .graphite])
        XCTAssertTrue(routes.allSatisfy { $0.snapshot == nil })
        XCTAssertEqual(routes[0].shownName, "Meetings")
        XCTAssertEqual(routes[3].shownName, "Icon-only Route")
    }

    func testCurrentSummaryRoundTripsInitialStyleAndSnapshot() {
        let snapshotData = Data(#"{"id":"journal"}"#.utf8)
        let summary = WatchCapturePresetSummary(
            id: "journal",
            displayName: "Journal",
            visibleName: "journal",
            initial: "j",
            tileStyle: .graphite,
            snapshot: snapshotData
        )
        XCTAssertEqual(summary.initial, "J")

        let decoded = WatchCapturePresetSummary(dictionary: summary.dictionary, index: 0)
        XCTAssertEqual(decoded, summary)
    }

    func testUnknownTileStyleFailsClosedToAccent() {
        let decoded = WatchCapturePresetSummary(dictionary: [
            WatchRecordingPayloadKey.selectedPresetID: "x",
            WatchRecordingPayloadKey.selectedPresetName: "Xylophone",
            WatchRecordingPayloadKey.presetTileStyle: "neon",
        ], index: 3)
        XCTAssertEqual(decoded?.tileStyle, .accent)
        XCTAssertEqual(decoded?.initial, "X")
    }

    func testQueuedRouteNamesSurviveLocalSnapshotStore() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WatchRouteSummaryPayloadTests"))
        defaults.removePersistentDomain(forName: "WatchRouteSummaryPayloadTests")
        let snapshot = WatchRecordingSnapshot(
            phase: .idle,
            isQuickRecordEnabled: true,
            queuedCount: 2,
            selectedPresetID: "inbox",
            selectedPresetName: "Inbox",
            queuedRouteNames: ["Journal", "Inbox"]
        )
        WatchLocalSnapshotStore.save(snapshot, defaults: defaults)
        let loaded = try XCTUnwrap(WatchLocalSnapshotStore.load(defaults: defaults))
        XCTAssertEqual(loaded.queuedRouteNames, ["Journal", "Inbox"])
        XCTAssertEqual(loaded.selectedPresetName, "Inbox")
        XCTAssertEqual(loaded.queuedCount, 2)
    }

    func testRouteDeepLinkCarriesRouteID() {
        let url = WatchRecordingDeepLink.startURL(routeID: "route with space")
        XCTAssertEqual(url.host, WatchRecordingDeepLink.startHost)
        XCTAssertEqual(WatchRecordingDeepLink.routeID(from: url), "route with space")
        XCTAssertEqual(WatchRecordingDeepLink.startURL(routeID: nil), WatchRecordingDeepLink.startURL)
        XCTAssertNil(WatchRecordingDeepLink.routeID(from: WatchRecordingDeepLink.toggleURL))
    }
}
