import AppIntents
import VoxboardCaptureCore
import XCTest

/// Compiles the real lightweight widget intent/query in this target, not the
/// widget @main bundle or the app's composer-intent implementation.
final class CapturePresetWidgetConfigurationTests: XCTestCase {
    func testActualQueryKeepsRequestedOrderAndStaleIdentifiers() async throws {
        let profiles = [profile("a"), profile("b", enabled: false), profile("c"), profile("b")]
        let query = CapturePresetWidgetEntityQuery(readProfiles: { profiles })
        let entities = try await query.entities(for: ["c", "missing", "b", "a", "c"])
        XCTAssertEqual(entities.map(\.id), ["c", "missing", "b", "a"])
        XCTAssertNil(entities[1].identity)
        XCTAssertEqual(entities[2].identity?.isEnabled, false)
        let suggested = try await query.suggestedEntities()
        let all = try await query.allEntities()
        XCTAssertEqual(suggested.map(\.id), ["a", "c"])
        XCTAssertEqual(all, suggested)
        let defaultEntity = await query.defaultResult()
        XCTAssertNil(defaultEntity, "Empty custom positions must never borrow a selected/default preset")
    }

    func testUnavailableQueryDoesNotForgetSavedIDsOrInventSuggestions() async throws {
        let query = CapturePresetWidgetEntityQuery(readProfiles: { nil })
        let entities = try await query.entities(for: ["gone", "gone", "other"])
        XCTAssertEqual(entities.map(\.id), ["gone", "other"])
        XCTAssertTrue(entities.allSatisfy { $0.identity == nil })
        let suggested = try await query.suggestedEntities()
        XCTAssertTrue(suggested.isEmpty)
    }

    func testActualConfigurationDefaultsToFollowAndSnapshotsSixExplicitPositions() async throws {
        let intent = CapturePresetWidgetConfiguration()
        XCTAssertEqual(intent.source, .followCaptureBar)
        XCTAssertEqual(intent.selection, .followCaptureBar)
        let profiles = [profile("a"), profile("b")]
        let query = CapturePresetWidgetEntityQuery(readProfiles: { profiles })
        let entities = try await query.entities(for: ["b", "a"])
        intent.source = .custom
        intent.first = entities[0]
        intent.third = entities[1]
        intent.sixth = entities[0]
        let value = intent.selection
        XCTAssertEqual(value, .custom(slots: ["b", nil, "a", nil, nil, "b"]))
        intent.first = entities[1]
        intent.source = .followCaptureBar
        XCTAssertEqual(value, .custom(slots: ["b", nil, "a", nil, nil, "b"]), "Entry values cannot retain mutable IntentParameters")
        XCTAssertEqual(intent.selection, .followCaptureBar)
        _ = CapturePresetWidgetConfiguration.parameterSummary
    }

    private func profile(_ id: String, enabled: Bool = true) -> CapturePresetProfile {
        CapturePresetProfile(id: id, name: id, symbolName: "waveform", isEnabled: enabled)
    }
}
