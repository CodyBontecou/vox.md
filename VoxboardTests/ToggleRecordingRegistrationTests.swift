import AppIntents
import VoxboardShared
import XCTest
@testable import Voxboard

@available(iOS 26.0, *)
@MainActor
final class ToggleRecordingRegistrationTests: XCTestCase {
    func testControlPassesConfiguredPresetToExistingBackgroundIntent() async throws {
        try await withPresets { selected, configured, _, _ in
            let configuration = SelectVoxboardRecordVoxIntent(vox: VoxEntity(flow: configured))
            let provider = VoxboardToggleRecordingControl.Provider()
            let preview = provider.previewValue(configuration: configuration)
            let current = try await provider.currentValue(configuration: configuration)
            XCTAssertEqual(preview.vox.id, configured.id)
            XCTAssertEqual(current.action.vox?.id, configured.id)
            XCTAssertNotEqual(current.action.vox?.id, selected.id)
            XCTAssertTrue(current.isEnabled)
            XCTAssertFalse(ToggleVoxboardRecordingIntent.openAppWhenRun)
            XCTAssertEqual(ToggleVoxboardRecordingIntent.supportedModes, [.background, .foreground(.dynamic)])
            XCTAssertTrue(current.action is any AudioRecordingIntent)
            XCTAssertTrue(current.action is any LiveActivityIntent)
        }
    }

    func testControlFallsBackForMissingOrDisabledPreset() async throws {
        try await withPresets { selected, _, disabled, _ in
            let provider = VoxboardToggleRecordingControl.Provider()
            for entity in [nil, VoxEntity(flow: disabled), VoxEntity(id: "deleted", name: "Deleted", symbolName: "mic")] {
                let state = try await provider.currentValue(configuration: SelectVoxboardRecordVoxIntent(vox: entity))
                XCTAssertEqual(state.action.vox?.id, selected.id)
            }
        }
    }

    func testSafetySettingDisablesControlAndExistingWrapperIntent() async throws {
        try await withPresets { _, configured, _, defaults in
            defaults.set(false, forKey: AppConstants.lockScreenQuickRecordEnabledKey)
            let state = try await VoxboardToggleRecordingControl.Provider().currentValue(
                configuration: SelectVoxboardRecordVoxIntent(vox: VoxEntity(flow: configured))
            )
            XCTAssertFalse(state.isEnabled)
            // Exercise the real perform path without microphone/device permission.
            defaults.removeObject(forKey: AppConstants.pendingWidgetRecordKey)
            _ = try await state.action.perform()
            XCTAssertNil(defaults.object(forKey: AppConstants.pendingWidgetRecordKey))
        }
    }

    func testStopWithoutLiveActivityTearsDownRemainingAudioSession() {
        var segmentActive = true
        var audioSessionActive = true
        var finishedRecording = false

        ToggleVoxboardRecordingIntent.stopRecording(
            stopSegment: {
                // A background stop finalizes the recording, but the recorder
                // can retain its audio session while queued processing runs.
                segmentActive = false
                finishedRecording = true
            },
            ensureLiveActivity: { false },
            stopListening: {
                XCTAssertTrue(finishedRecording, "Finalize before tearing down capture")
                audioSessionActive = false
            }
        )

        XCTAssertFalse(segmentActive)
        XCTAssertTrue(finishedRecording)
        XCTAssertFalse(audioSessionActive, "An audio recording intent must not return with audio capture active and no Live Activity")
    }

    func testStopWithLiveActivityKeepsBackgroundProcessingSession() {
        var segmentActive = true
        var audioSessionActive = true

        ToggleVoxboardRecordingIntent.stopRecording(
            stopSegment: { segmentActive = false },
            ensureLiveActivity: {
                XCTAssertFalse(segmentActive, "Stop the segment before updating its activity")
                return true
            },
            stopListening: { audioSessionActive = false }
        )

        XCTAssertFalse(segmentActive)
        XCTAssertTrue(audioSessionActive, "Keep the existing background processing lease when its Live Activity is available")
    }

    func testBuiltAppRegistersBackgroundAndLegacyAppShortcuts() throws {
        let metadata = try actionsMetadata(in: Bundle.main.bundleURL)
        let shortcuts = try XCTUnwrap(metadata["autoShortcuts"])
        let serialized = String(decoding: try JSONSerialization.data(withJSONObject: shortcuts), as: UTF8.self)
        XCTAssertTrue(serialized.contains("ToggleVoxboardRecordingIntent"), serialized)
        XCTAssertTrue(serialized.contains("OpenVoxboardRecordIntent"), serialized)
        XCTAssertTrue(OpenVoxboardRecordIntent.openAppWhenRun)
    }

    func testBuiltAppPreservesLegacyShortcutAvailabilityBelowIOS26() throws {
        let metadata = try actionsMetadata(in: Bundle.main.bundleURL)
        let shortcuts = try XCTUnwrap(metadata["autoShortcuts"] as? [[String: Any]])
        let legacyActions = [
            "OpenVoxboardRecordIntent", "OpenQuickCaptureIntent", "OpenCaptureVoiceIntent",
            "OpenCaptureScreenshotIntent", "OpenCaptureScanIntent", "CaptureTextIntent",
            "CaptureURLIntent", "CaptureFileIntent"
        ]
        for identifier in legacyActions + ["ToggleVoxboardRecordingIntent"] {
            let shortcut = try XCTUnwrap(shortcuts.first { $0["actionIdentifier"] as? String == identifier })
            let availability = try XCTUnwrap(shortcut["availabilityAnnotations"] as? [String: Any])
            let iOS = try XCTUnwrap(availability["LNPlatformNameIOS"] as? [String: Any])
            let introducedVersion = try XCTUnwrap(iOS["introducedVersion"] as? String)
            if identifier == "ToggleVoxboardRecordingIntent" {
                XCTAssertEqual(introducedVersion, "26.0")
            } else {
                XCTAssertNotEqual(
                    introducedVersion.compare("17.6", options: .numeric), .orderedDescending,
                    "\(identifier) must remain available on the supported iOS 17.6 deployment target, not require \(introducedVersion)"
                )
            }
        }
    }

    func testEmbeddedWidgetCarriesSameToggleIntentIdentity() throws {
        let plugins = Bundle.main.bundleURL.appendingPathComponent("PlugIns")
        let extensionURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent == "Voxboard WidgetExtension.appex" }
        )
        let metadata = try actionsMetadata(in: extensionURL)
        let serialized = String(decoding: try JSONSerialization.data(withJSONObject: metadata), as: UTF8.self)
        XCTAssertTrue(serialized.contains("ToggleVoxboardRecordingIntent"))
        XCTAssertTrue(serialized.contains("SelectVoxboardRecordVoxIntent"))
        XCTAssertNotEqual(VoxboardToggleRecordingControl.kind, "VoxboardRecordControl")
    }

    private func actionsMetadata(in bundle: URL) throws -> [String: Any] {
        let url = bundle.appendingPathComponent("Metadata.appintents/extract.actionsdata")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func withPresets(
        _ body: (CapturePreset, CapturePreset, CapturePreset, UserDefaults) async throws -> Void
    ) async throws {
        // Intent/query APIs use the shared suite. Restore every touched key; this
        // runs only in the ephemeral CI simulator, never against a user's data.
        let defaults = try XCTUnwrap(AppConstants.sharedDefaults)
        let keys = [CapturePresetStore.flowsKey, CapturePresetStore.selectedFlowIdKey,
                    AppConstants.lockScreenQuickRecordEnabledKey, AppConstants.pendingWidgetRecordKey]
        let originals = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, original) in zip(keys, originals) {
                if let original { defaults.set(original, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        var selected = CapturePresetStore.makeCustomFlow()
        selected.id = "registration-selected"
        var configured = CapturePresetStore.makeCustomFlow()
        configured.id = "registration-configured"
        var disabled = CapturePresetStore.makeCustomFlow()
        disabled.id = "registration-disabled"
        disabled.isEnabled = false
        defaults.set(try JSONEncoder().encode([selected, configured, disabled]), forKey: CapturePresetStore.flowsKey)
        defaults.set(selected.id, forKey: CapturePresetStore.selectedFlowIdKey)
        defaults.set(true, forKey: AppConstants.lockScreenQuickRecordEnabledKey)
        try await body(selected, configured, disabled, defaults)
    }
}
