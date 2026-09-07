import XCTest
@testable import Voxboard

@MainActor
final class CaptureMicHoldHintTests: XCTestCase {
    func testCompletionKeyIsStableAndNewUsersHaveNotDismissed() throws {
        XCTAssertEqual(CapturePreferenceKeys.micHoldHintDismissed, "capture.voice.micHoldHintDismissed.v1")
        let (defaults, _) = try makeDefaults()
        XCTAssertFalse(defaults.bool(forKey: CapturePreferenceKeys.micHoldHintDismissed))
    }

    func testCompletionSurvivesReloadAndToolbarReset() throws {
        let (defaults, suiteName) = try makeDefaults()
        defaults.set(true, forKey: CapturePreferenceKeys.micHoldHintDismissed)

        let preferences = CaptureToolbarPreferences(defaults: defaults)
        preferences.reset()
        preferences.setConfirmsVoiceNotesBeforeAdding(true)

        let reloaded = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertTrue(reloaded.bool(forKey: CapturePreferenceKeys.micHoldHintDismissed))
    }

    func testBubbleStaysOnScreenAndArrowTracksMicAtEitherEdge() {
        for containerWidth: CGFloat in [320, 390, 430, 768, 1024] {
            // Both sides cover LTR/RTL bars and future mic placement changes.
            for micMidX: CGFloat in [30, 74, containerWidth / 2, containerWidth - 74, containerWidth - 30] {
                let placement = CaptureMicHoldHintPlacement(containerWidth: containerWidth, micMidX: micMidX)
                XCTAssertLessThanOrEqual(placement.width, 280)
                XCTAssertGreaterThanOrEqual(placement.minX, 12)
                XCTAssertLessThanOrEqual(placement.minX + placement.width, containerWidth - 12)
                XCTAssertEqual(placement.minX + placement.arrowX, micMidX, accuracy: 0.001)
                XCTAssertGreaterThanOrEqual(placement.arrowX, 12)
                XCTAssertLessThanOrEqual(placement.arrowX, placement.width - 12)
            }
        }
    }

    func testBubbleShrinksToFitCompactContainer() {
        let placement = CaptureMicHoldHintPlacement(containerWidth: 260, micMidX: 200)
        XCTAssertEqual(placement.width, 236)
        XCTAssertEqual(placement.minX, 12)
        XCTAssertEqual(placement.arrowX, 188)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "CaptureMicHoldHintTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return (defaults, suiteName)
    }
}
