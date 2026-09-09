import VoxboardShared
import XCTest
@testable import Voxboard

@MainActor
final class CaptureToolbarPreferencesTests: XCTestCase {
    func test_newExtractTextActionFollowsDocumentScanByDefault() throws {
        let order = CaptureToolbarPreferences.migratedActionOrder(from: nil)
        let scanIndex = try XCTUnwrap(order.firstIndex(of: .scanDocument))

        XCTAssertEqual(order[scanIndex + 1], .extractText)
    }

    func test_migrationPreservesCustomOrderAndInsertsExtractTextAfterScan() {
        let order = CaptureToolbarPreferences.migratedActionOrder(from: [
            "undo",
            "scanDocument",
            "addMedia",
            "undo",
            "retired-action",
        ])

        XCTAssertEqual(Array(order.prefix(4)), [
            .undo,
            .scanDocument,
            .extractText,
            .addMedia,
        ])
        XCTAssertEqual(order.filter { $0 == .undo }.count, 1)
        XCTAssertEqual(Set(order), Set(CaptureToolbarAction.allCases))
    }

    func testRailSideAndTimestampFormatHaveStableKeysRawValuesAndDefaults() throws {
        XCTAssertEqual(
            CapturePreferenceKeys.presetQuickAccessRailSide,
            "capture.presets.quickAccess.railSide.v1"
        )
        XCTAssertEqual(
            CapturePreferenceKeys.timestampFormat,
            "capture.toolbar.timestampFormat.v1"
        )
        XCTAssertEqual(CapturePresetQuickAccessRailSide.left.rawValue, "left")
        XCTAssertEqual(CapturePresetQuickAccessRailSide.right.rawValue, "right")
        XCTAssertEqual(CapturePresetQuickAccessRailSide.allCases, [.left, .right])
        XCTAssertEqual(CapturePresetQuickAccessRailSide.default, .left)
        XCTAssertEqual(CaptureTimestampFormat.twelveHour.rawValue, "12-hour")
        XCTAssertEqual(CaptureTimestampFormat.twentyFourHour.rawValue, "24-hour")
        XCTAssertEqual(CaptureTimestampFormat.default, .twelveHour)

        let (defaults, _) = try makeDefaults()
        XCTAssertNil(defaults.object(forKey: CapturePreferenceKeys.presetQuickAccessRailSide))
        XCTAssertNil(defaults.object(forKey: CapturePreferenceKeys.timestampFormat))
        let preferences = CaptureToolbarPreferences(defaults: defaults)
        XCTAssertEqual(preferences.presetQuickAccessRailSide, .left)
        XCTAssertEqual(preferences.timestampFormat, .twelveHour)
    }

    func testUnknownRailSideAndTimestampFormatResolveDefensivelyWithoutDeviceInference() throws {
        let (defaults, _) = try makeDefaults()
        defaults.set("center", forKey: CapturePreferenceKeys.presetQuickAccessRailSide)
        defaults.set("automatic", forKey: CapturePreferenceKeys.timestampFormat)

        let preferences = CaptureToolbarPreferences(defaults: defaults)

        XCTAssertEqual(preferences.presetQuickAccessRailSide, .left)
        XCTAssertEqual(preferences.timestampFormat, .twelveHour)
        XCTAssertEqual(defaults.string(forKey: CapturePreferenceKeys.presetQuickAccessRailSide), "center")
        XCTAssertEqual(defaults.string(forKey: CapturePreferenceKeys.timestampFormat), "automatic")
    }

    func testRailSideAndTimestampSettersPersistEveryExplicitChoiceAcrossReload() throws {
        let (defaults, suiteName) = try makeDefaults()
        let preferences = CaptureToolbarPreferences(defaults: defaults)

        preferences.setPresetQuickAccessRailSide(.right)
        preferences.setTimestampFormat(.twentyFourHour)
        XCTAssertEqual(defaults.string(forKey: CapturePreferenceKeys.presetQuickAccessRailSide), "right")
        XCTAssertEqual(defaults.string(forKey: CapturePreferenceKeys.timestampFormat), "24-hour")

        var reopened = CaptureToolbarPreferences(
            defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName))
        )
        XCTAssertEqual(reopened.presetQuickAccessRailSide, .right)
        XCTAssertEqual(reopened.timestampFormat, .twentyFourHour)

        reopened.setPresetQuickAccessRailSide(.left)
        reopened.setTimestampFormat(.twelveHour)
        reopened = CaptureToolbarPreferences(
            defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName))
        )
        XCTAssertEqual(reopened.presetQuickAccessRailSide, .left)
        XCTAssertEqual(reopened.timestampFormat, .twelveHour)
        XCTAssertEqual(defaults.string(forKey: CapturePreferenceKeys.presetQuickAccessRailSide), "left")
        XCTAssertEqual(defaults.string(forKey: CapturePreferenceKeys.timestampFormat), "12-hour")
    }

    func testToolbarResetLeavesEachRailSideAndTimestampChoiceIndependent() throws {
        for side in CapturePresetQuickAccessRailSide.allCases {
            for format in CaptureTimestampFormat.allCases {
                let (defaults, suiteName) = try makeDefaults()
                let preferences = CaptureToolbarPreferences(defaults: defaults)
                preferences.setPresetQuickAccessRailSide(side)
                preferences.setTimestampFormat(format)
                preferences.setVisible(false, for: .timestamp)

                preferences.reset()

                let reopened = CaptureToolbarPreferences(
                    defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName))
                )
                XCTAssertTrue(reopened.isVisible(.timestamp))
                XCTAssertEqual(reopened.presetQuickAccessRailSide, side)
                XCTAssertEqual(reopened.timestampFormat, format)
            }
        }
    }

    func testPersistedTimestampSelectionReachesDeterministicComposerConsumer() throws {
        let (defaults, suiteName) = try makeDefaults()
        defaults.set(CaptureTimestampFormat.twentyFourHour.rawValue,
                     forKey: CapturePreferenceKeys.timestampFormat)
        let preferences = CaptureToolbarPreferences(
            defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName))
        )
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = CaptureInsertionFormatter(
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone
        )
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 1,
            day: 2,
            hour: 15,
            minute: 4
        )))

        XCTAssertEqual(
            QuickCaptureView.timestampInsertion(
                at: date,
                formatter: formatter,
                preferences: preferences
            ),
            "15:04 2026-01-02"
        )

        preferences.setTimestampFormat(.twelveHour)
        XCTAssertEqual(
            QuickCaptureView.timestampInsertion(
                at: date,
                formatter: formatter,
                preferences: preferences
            ),
            "3:04 PM 2026-01-02"
        )
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "CaptureToolbarPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return (defaults, suiteName)
    }
}
