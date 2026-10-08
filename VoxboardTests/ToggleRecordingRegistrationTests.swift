import AppIntents
import VoxboardShared
import XCTest
@testable import Voxboard

@available(iOS 26.0, *)
@MainActor
final class ToggleRecordingRegistrationTests: XCTestCase {
    func testLegacyBackgroundControlKeepsItsPresetAndStartStopDefaults() async throws {
        try await withPresets { selected, configured, _, _ in
            let configuration = SelectVoxboardRecordVoxIntent(vox: VoxEntity(flow: configured))
            let provider = VoxboardToggleRecordingControl.Provider()
            let preview = provider.previewValue(configuration: configuration)
            let current = try await provider.currentValue(configuration: configuration)
            XCTAssertEqual(preview.vox.id, configured.id)
            XCTAssertEqual(current.action.vox?.id, configured.id)
            XCTAssertNotEqual(current.action.vox?.id, selected.id)
            XCTAssertEqual(current.action.recordingAction, .toggle)
            XCTAssertFalse(current.action.openApp)
            XCTAssertTrue(current.isEnabled)
            XCTAssertFalse(ToggleVoxboardRecordingIntent.openAppWhenRun)
            XCTAssertEqual(ToggleVoxboardRecordingIntent.supportedModes, [.background, .foreground(.dynamic)])
            XCTAssertTrue(current.action is any AudioRecordingIntent)
            XCTAssertTrue(current.action is any LiveActivityIntent)
        }
    }

    func testExistingForegroundControlKeepsStartAndOpenAppDefaults() async throws {
        try await withPresets { _, configured, _, _ in
            let configuration = SelectVoxboardRecordVoxIntent(vox: VoxEntity(flow: configured))
            XCTAssertNil(configuration.recordingAction)
            XCTAssertNil(configuration.openApp)
            XCTAssertNil(configuration.delivery)
            XCTAssertNil(configuration.attachAudio)
            let state = try await VoxboardRecordingControlProvider().currentValue(configuration: configuration)
            XCTAssertEqual(state.action.recordingAction, .start)
            XCTAssertTrue(state.action.openApp)
            XCTAssertEqual(state.action.delivery, .immediate)
            XCTAssertFalse(state.action.attachAudio)
            XCTAssertEqual(state.action.vox?.id, configured.id)
        }
    }

    func testBothControlKindsForwardExplicitActionAndPresentation() async throws {
        try await withPresets { _, configured, _, _ in
            for action in RecordingAction.allCases {
                for openApp in [false, true] {
                    let configuration = SelectVoxboardRecordVoxIntent(vox: VoxEntity(flow: configured), action: action, openApp: openApp)
                    let record = try await VoxboardRecordingControlProvider().currentValue(configuration: configuration)
                    let legacy = try await VoxboardToggleRecordingControl.Provider().currentValue(configuration: configuration)
                    for state in [record, legacy] {
                        XCTAssertEqual(state.action.recordingAction, action)
                        XCTAssertEqual(state.action.openApp, openApp)
                        XCTAssertEqual(state.action.vox?.id, configured.id)
                    }
                }
            }
        }
    }

    func testControlsFallBackForMissingDeletedOrDisabledPreset() async throws {
        try await withPresets { selected, _, disabled, _ in
            for entity in [nil, VoxEntity(flow: disabled), VoxEntity(id: "deleted", name: "Deleted", symbolName: "mic")] {
                let configuration = SelectVoxboardRecordVoxIntent(vox: entity)
                let record = try await VoxboardRecordingControlProvider().currentValue(configuration: configuration)
                let legacy = try await VoxboardToggleRecordingControl.Provider().currentValue(configuration: configuration)
                XCTAssertEqual(record.action.vox?.id, selected.id)
                XCTAssertEqual(legacy.action.vox?.id, selected.id)
            }
        }
    }

    func testBothControlKindsForwardDraftDeliveryAndAudioWithoutRewritingPresentation() async throws {
        try await withPresets { _, configured, _, _ in
            for action in RecordingAction.allCases {
                for attachAudio in [false, true] {
                    let configuration = SelectVoxboardRecordVoxIntent(vox: VoxEntity(flow: configured), action: action, openApp: false, delivery: .draft, attachAudio: attachAudio)
                    let record = try await VoxboardRecordingControlProvider().currentValue(configuration: configuration)
                    let legacy = try await VoxboardToggleRecordingControl.Provider().currentValue(configuration: configuration)
                    for state in [record, legacy] {
                        XCTAssertEqual(state.action.recordingAction, action)
                        XCTAssertEqual(state.action.delivery, .draft)
                        XCTAssertEqual(state.action.attachAudio, attachAudio)
                        XCTAssertFalse(state.action.openApp)
                        XCTAssertEqual(state.action.vox?.id, configured.id)
                        XCTAssertFalse(state.actionHint.contains("without switching apps"), "Draft execution always opens the review composer")
                    }
                }
            }
        }
    }

    func testSafetySettingDisablesControlsAndBothIntentPaths() async throws {
        try await withPresets { _, configured, _, defaults in
            defaults.set(false, forKey: AppConstants.lockScreenQuickRecordEnabledKey)
            let configuration = SelectVoxboardRecordVoxIntent(vox: VoxEntity(flow: configured))
            let record = try await VoxboardRecordingControlProvider().currentValue(configuration: configuration)
            let legacy = try await VoxboardToggleRecordingControl.Provider().currentValue(configuration: configuration)
            XCTAssertFalse(record.isEnabled)
            XCTAssertFalse(legacy.isEnabled)
            for action in RecordingAction.allCases {
                for openApp in [false, true] {
                    defaults.removeObject(forKey: AppConstants.pendingWidgetRecordKey)
                    defaults.removeObject(forKey: WidgetRecordingActionSelection.key)
                    _ = try await VoxboardRecordingControlIntent(vox: VoxEntity(flow: configured), action: action, openApp: openApp).perform()
                    XCTAssertNil(defaults.object(forKey: AppConstants.pendingWidgetRecordKey))
                    XCTAssertNil(defaults.object(forKey: WidgetRecordingActionSelection.key))
                }
            }
            for action in RecordingAction.allCases {
                _ = try await OpenVoxboardRecordIntent(vox: VoxEntity(flow: configured), action: action).perform()
                XCTAssertNil(defaults.object(forKey: AppConstants.pendingWidgetRecordKey))
            }
            _ = try await ToggleVoxboardRecordingIntent(vox: VoxEntity(flow: configured)).perform()
            XCTAssertNil(defaults.object(forKey: AppConstants.pendingWidgetRecordKey))
        }
    }

    func testBackgroundToggleStopWithoutLiveActivityTearsDownRemainingAudioSession() {
        var segmentActive = true
        var audioSessionActive = true
        var events: [String] = []
        let outcome = BackgroundRecordingAction.perform(
            action: .toggle,
            flowID: nil,
            effects: .init(
                isRecording: { segmentActive },
                start: { _ in XCTFail("Stop must not start another recording"); return false },
                stop: { segmentActive = false; events.append("finalize") },
                stopListening: { audioSessionActive = false; events.append("release") },
                ensureLiveActivity: { events.append("activity"); return false },
                endShortcutActivity: { events.append("endActivity") }
            )
        )
        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(events, ["finalize", "activity", "release", "endActivity"])
        XCTAssertFalse(segmentActive)
        XCTAssertFalse(audioSessionActive)
    }

    func testBackgroundToggleStopWithLiveActivityKeepsBackgroundProcessingSession() {
        var segmentActive = true
        var audioSessionActive = true
        let outcome = BackgroundRecordingAction.perform(
            action: .toggle,
            flowID: nil,
            effects: .init(
                isRecording: { segmentActive },
                start: { _ in XCTFail("Stop must not start another recording"); return false },
                stop: { segmentActive = false },
                stopListening: { audioSessionActive = false },
                ensureLiveActivity: {
                    XCTAssertFalse(segmentActive, "Finalize before updating the activity")
                    return true
                },
                endShortcutActivity: { XCTFail("Keep the active background processing activity") }
            )
        )
        XCTAssertEqual(outcome, .completed)
        XCTAssertFalse(segmentActive)
        XCTAssertTrue(audioSessionActive)
    }

    func testBuiltAppPreservesLegacyShortcutAvailabilityBelowIOS26() throws {
        let metadata = try actionsMetadata(in: Bundle.main.bundleURL)
        let shortcuts = try XCTUnwrap(metadata["autoShortcuts"] as? [[String: Any]])
        let legacyActions = [
            "OpenVoxboardRecordIntent", "OpenQuickCaptureIntent", "OpenCaptureVoiceIntent",
            "OpenCaptureScreenshotIntent", "OpenCaptureScanIntent", "CaptureTextIntent",
            "CaptureURLIntent", "CaptureFileIntent"
        ]
        for identifier in legacyActions {
            let shortcut = try XCTUnwrap(shortcuts.first { $0["actionIdentifier"] as? String == identifier })
            let availability = try XCTUnwrap(shortcut["availabilityAnnotations"] as? [String: Any])
            let iOS = try XCTUnwrap(availability["LNPlatformNameIOS"] as? [String: Any])
            let introducedVersion = try XCTUnwrap(iOS["introducedVersion"] as? String)
            XCTAssertNotEqual(
                introducedVersion.compare("17.6", options: .numeric), .orderedDescending,
                "\(identifier) must remain available on iOS 17.6, not require \(introducedVersion)"
            )
        }
        let actions = try XCTUnwrap(metadata["actions"] as? [String: [String: Any]])
        let toggle = try XCTUnwrap(actions["ToggleVoxboardRecordingIntent"])
        let availability = try XCTUnwrap(toggle["availabilityAnnotations"] as? [String: [String: Any]])
        XCTAssertEqual(availability["LNPlatformNameIOS"]?["introducedVersion"] as? String, "26.0")
    }

    func testPrimaryUsesNativeForegroundPreferenceAndControlsUseHiddenDispatcher() {
        XCTAssertTrue(OpenVoxboardRecordIntent.openAppWhenRun, "Older iOS retains its foreground launch default")
        XCTAssertTrue(OpenVoxboardRecordIntent.supportedModes.contains(.background))
        XCTAssertTrue(OpenVoxboardRecordIntent.supportedModes.contains(.foreground(.immediate)))
        XCTAssertFalse(OpenVoxboardRecordIntent.supportedModes.contains(.foreground(.dynamic)))
        XCTAssertTrue(OpenVoxboardRecordIntent.isDiscoverable)
        XCTAssertFalse(VoxboardRecordingControlIntent.isDiscoverable)
        XCTAssertEqual(VoxboardRecordingControlIntent.supportedModes, .background)
        XCTAssertFalse(ToggleVoxboardRecordingIntent.isDiscoverable)
        XCTAssertFalse(OpenVoxboardRecordingActionIntent.isDiscoverable)
        XCTAssertTrue(OpenVoxboardRecordingActionIntent.openAppWhenRun)
    }

    func testPrimaryDoesNotExportACompetingCustomLaunchParameter() throws {
        let metadata = try actionsMetadata(in: Bundle.main.bundleURL)
        let actions = try XCTUnwrap(metadata["actions"] as? [String: [String: Any]])
        let recording = try XCTUnwrap(actions["OpenVoxboardRecordIntent"])
        let parameters = try XCTUnwrap(recording["parameters"] as? [[String: Any]])
        XCTAssertEqual(Set(parameters.compactMap { $0["name"] as? String }), ["vox", "recordingAction", "delivery", "attachAudio"],
                       "Shortcuts owns Open When Run; exporting Open App creates a competing foreground control")
    }

    func testCurrentOSProvidesOneConfigurableRecordingShortcutAndAllCaptureShortcuts() {
        let shortcuts = VoxboardShortcutsProvider.appShortcuts
        XCTAssertEqual(shortcuts.count, 8, "Record Audio handles both deliveries and retains all seven capture shortcuts")
    }

    func testAppAndWidgetDoNotExportSeparateDraftRecordingActions() throws {
        let plugins = Bundle.main.bundleURL.appendingPathComponent("PlugIns")
        let extensionURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent == "Voxboard WidgetExtension.appex" }
        )
        for bundle in [Bundle.main.bundleURL, extensionURL] {
            let metadata = try actionsMetadata(in: bundle)
            let actions = try XCTUnwrap(metadata["actions"] as? [String: [String: Any]])
            XCTAssertNil(actions["RecordToDraftIntent"])
            XCTAssertNil(actions["SelectVoxboardDraftRecordVoxIntent"])
            XCTAssertNotNil(actions["OpenVoxboardRecordIntent"])
            XCTAssertNotNil(actions["SelectVoxboardRecordVoxIntent"])
            let shortcuts = metadata["autoShortcuts"] as? [[String: Any]] ?? []
            XCTAssertFalse(shortcuts.contains { $0["actionIdentifier"] as? String == "RecordToDraftIntent" })
        }
    }

    func testBuiltAppRegistersConfigurableActionAndCompatibilityIdentities() throws {
        let metadata = try actionsMetadata(in: Bundle.main.bundleURL)
        let actions = try XCTUnwrap(metadata["actions"] as? [String: [String: Any]])
        let recording = try XCTUnwrap(actions["OpenVoxboardRecordIntent"])
        XCTAssertEqual(recording["isDiscoverable"] as? Bool, true)
        XCTAssertEqual(recording["outputFlags"] as? Int, 1, "OpensIntent must be declared in the perform signature, not just inferred from its container")
        XCTAssertEqual(recording["openAppWhenRun"] as? Bool, true)
        XCTAssertEqual(recording["supportedModes"] as? Int, 3, "Foreground-preferred default with background supported; native Open When Run selects the mode")
        let availability = try XCTUnwrap(recording["availabilityAnnotations"] as? [String: [String: Any]])
        XCTAssertEqual(availability["LNPlatformNameIOS"]?["introducedVersion"] as? String, "17.0")
        let parameters = try XCTUnwrap(recording["parameters"] as? [[String: Any]])
        XCTAssertEqual(Set(parameters.compactMap { $0["name"] as? String }), ["vox", "recordingAction", "delivery", "attachAudio"])
        let actionParameter = try XCTUnwrap(parameters.first { $0["name"] as? String == "recordingAction" })
        let actionMetadata = try XCTUnwrap(actionParameter["typeSpecificMetadata"] as? [Any])
        XCTAssertEqual((actionMetadata.last as? [String: [String: String]])?["string"]?["wrapper"], "start")
        let deliveryParameter = try XCTUnwrap(parameters.first { $0["name"] as? String == "delivery" })
        let deliveryMetadata = try XCTUnwrap(deliveryParameter["typeSpecificMetadata"] as? [Any])
        XCTAssertEqual((deliveryMetadata.last as? [String: [String: String]])?["string"]?["wrapper"], "immediate")
        let protocols = try XCTUnwrap(recording["systemProtocols"] as? [String])
        XCTAssertTrue(protocols.contains("com.apple.link.systemProtocol.AudioRecording"))
        XCTAssertTrue(protocols.contains("com.apple.link.systemProtocol.SessionStarting"))
        XCTAssertFalse(protocols.contains("com.apple.link.systemProtocol.ForegroundContinuable"), "A legacy conformance reintroduces the duplicate system Open When Run switch")

        for identifier in ["VoxboardRecordingControlIntent", "ToggleVoxboardRecordingIntent", "StartRecordingLiveActivityIntent", "StopRecordingLiveActivityIntent"] {
            let internalAction = try XCTUnwrap(actions[identifier], identifier)
            XCTAssertEqual(internalAction["isDiscoverable"] as? Bool, false, identifier)
        }
        XCTAssertEqual(actions["ToggleVoxboardRecordingIntent"]?["outputFlags"] as? Int, 1)
        let control = try XCTUnwrap(actions["VoxboardRecordingControlIntent"])
        XCTAssertEqual(control["outputFlags"] as? Int, 1)
        XCTAssertEqual(control["supportedModes"] as? Int, 1)
        let controlParameters = try XCTUnwrap(control["parameters"] as? [[String: Any]])
        XCTAssertEqual(Set(controlParameters.compactMap { $0["name"] as? String }), ["vox", "recordingAction", "openApp", "delivery", "attachAudio"])
        let foreground = try XCTUnwrap(actions["OpenVoxboardRecordingActionIntent"])
        XCTAssertEqual(foreground["isDiscoverable"] as? Bool, false)
        XCTAssertEqual(foreground["supportedModes"] as? Int, 2, "Foreground handoff retains immediate foreground execution")
        let shortcuts = try XCTUnwrap(metadata["autoShortcuts"] as? [[String: Any]])
        let identifiers = shortcuts.compactMap { $0["actionIdentifier"] as? String }
        XCTAssertEqual(identifiers.filter { $0 == "OpenVoxboardRecordIntent" }.count, 1)
        XCTAssertFalse(identifiers.contains("ToggleVoxboardRecordingIntent"))
        XCTAssertFalse(identifiers.contains("OpenVoxboardRecordingActionIntent"))
        XCTAssertFalse(identifiers.contains("VoxboardRecordingControlIntent"))
        for identifier in ["OpenQuickCaptureIntent", "OpenCaptureVoiceIntent", "OpenCaptureScreenshotIntent", "OpenCaptureScanIntent", "CaptureTextIntent", "CaptureURLIntent", "CaptureFileIntent"] {
            XCTAssertTrue(identifiers.contains(identifier), identifier)
        }
    }

    func testEmbeddedWidgetCarriesMatchingActionAndConfigurationParameters() throws {
        let plugins = Bundle.main.bundleURL.appendingPathComponent("PlugIns")
        let extensionURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent == "Voxboard WidgetExtension.appex" }
        )
        let metadata = try actionsMetadata(in: extensionURL)
        let actions = try XCTUnwrap(metadata["actions"] as? [String: [String: Any]])
        for identifier in ["OpenVoxboardRecordIntent", "VoxboardRecordingControlIntent", "OpenVoxboardRecordingActionIntent", "ToggleVoxboardRecordingIntent", "SelectVoxboardRecordVoxIntent"] {
            XCTAssertNotNil(actions[identifier], identifier)
        }
        let recording = try XCTUnwrap(actions["OpenVoxboardRecordIntent"])
        XCTAssertEqual(recording["supportedModes"] as? Int, 3)
        XCTAssertEqual(recording["openAppWhenRun"] as? Bool, true)
        let recordingParameters = try XCTUnwrap(recording["parameters"] as? [[String: Any]])
        XCTAssertEqual(Set(recordingParameters.compactMap { $0["name"] as? String }), ["vox", "recordingAction", "delivery", "attachAudio"])
        let configuration = try XCTUnwrap(actions["SelectVoxboardRecordVoxIntent"])
        let parameters = try XCTUnwrap(configuration["parameters"] as? [[String: Any]])
        XCTAssertEqual(Set(parameters.compactMap { $0["name"] as? String }), ["vox", "recordingAction", "openApp", "delivery", "attachAudio"])
        XCTAssertTrue(parameters.allSatisfy { $0["isOptional"] as? Bool == true }, "New optional fields must not rewrite saved configurations")
        XCTAssertEqual(VoxboardToggleRecordingControl.kind, "VoxboardToggleRecordingControl")
    }

    private func actionsMetadata(in bundle: URL) throws -> [String: Any] {
        let url = bundle.appendingPathComponent("Metadata.appintents/extract.actionsdata")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func withPresets(
        _ body: (CapturePreset, CapturePreset, CapturePreset, UserDefaults) async throws -> Void
    ) async throws {
        // Restore every touched key; this runs only in the CI/local test simulator.
        let defaults = try XCTUnwrap(AppConstants.sharedDefaults)
        let keys = [CapturePresetStore.flowsKey, CapturePresetStore.selectedFlowIdKey,
                    AppConstants.lockScreenQuickRecordEnabledKey, AppConstants.pendingWidgetRecordKey,
                    AppConstants.pendingWidgetRecordFlowIdKey, AppConstants.pendingWidgetRecordDraftAttachAudioKey, WidgetRecordingActionSelection.key]
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
