import AppIntents
import Foundation
import VoxboardShared

// MARK: - Capture Preset App Entity (legacy type name retained for App Intents)

struct VoxEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Capture Preset"
    static var defaultQuery = VoxEntityQuery()

    let id: String
    let name: String
    let symbolName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: symbolName)
        )
    }

    init(id: String, name: String, symbolName: String) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
    }

    init(flow: CapturePreset) {
        self.init(id: flow.id, name: flow.accessibilityName, symbolName: flow.symbolName)
    }

    static var fallback: VoxEntity {
        VoxEntity(flow: CapturePresetStore.selectedFlow())
    }

    static func resolved(_ entity: VoxEntity?) -> VoxEntity {
        guard let id = entity?.id,
              let flow = CapturePresetStore.flow(id: id),
              flow.isEnabled else {
            return fallback
        }
        return VoxEntity(flow: flow)
    }

    static func requestedFlowID(for entity: VoxEntity?) -> String? {
        guard let id = entity?.id,
              let flow = CapturePresetStore.flow(id: id), flow.isEnabled else { return nil }
        return flow.id
    }
}

struct VoxEntityQuery: EntityQuery, EnumerableEntityQuery {
    func entities(for identifiers: [VoxEntity.ID]) async throws -> [VoxEntity] {
        let requested = Set(identifiers)
        return Self.enabledVoxes().filter { requested.contains($0.id) }
    }

    func suggestedEntities() async throws -> [VoxEntity] {
        Self.enabledVoxes()
    }

    func allEntities() async throws -> [VoxEntity] {
        Self.enabledVoxes()
    }

    func defaultResult() async -> VoxEntity? {
        VoxEntity.fallback
    }

    private static func enabledVoxes() -> [VoxEntity] {
        let enabled = CapturePresetStore.loadFlows()
            .filter(\.isEnabled)
            .map(VoxEntity.init(flow:))
        return enabled.isEmpty ? CapturePresetStore.defaultFlows.map(VoxEntity.init(flow:)) : enabled
    }
}

// MARK: - Record Intent

@available(iOS 17.0, *)
struct OpenVoxboardRecordIntent: AppIntent {
    static let title: LocalizedStringResource = "Record Audio"
    static let description = IntentDescription("Start, stop, or start/stop a Vox.md recording with a Capture Preset. Turn off Open When Run to record without switching apps on iOS 26+. Recording opens Vox.md if setup is needed.")

    // Keep the saved Record action's foreground default, including older iOS.
    // Shortcuts owns the single Open When Run preference; do not export a
    // competing custom presentation parameter on this discoverable action.
    static var openAppWhenRun: Bool = true

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.immediate)] }

    @Parameter(title: "Preset", description: "The Capture Preset to use for this recording.")
    var vox: VoxEntity?

    // Keep Start for saved Record shortcuts whose serialized parameters
    // predate this choice. Choose Start or Stop for hardware keys.
    @Parameter(title: "Action", description: "Start and Stop leave an already-started or already-stopped recording unchanged. Start or Stop switches the current recording state.", default: .start)
    var recordingAction: RecordingAction

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$recordingAction) recording with \(\.$vox)")
    }

    init() {}

    init(vox: VoxEntity?, action: RecordingAction = .start) {
        self.vox = vox
        self.recordingAction = action
    }

    var foregroundIntent: OpenVoxboardRecordingActionIntent {
        OpenVoxboardRecordingActionIntent(vox: vox, action: recordingAction)
    }

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let openApp: Bool
        if #available(iOS 26.0, *), AppConstants.lockScreenQuickRecordEnabled {
            openApp = systemContext.currentMode == .foreground
        } else {
            openApp = true
        }
        return try await RecordingIntentExecution.perform(vox: vox, action: recordingAction, openApp: openApp)
    }
}

// Keep the public identity available on iOS 17; only iOS 26 opts into
// background audio/session execution. Older systems always open the app.
@available(iOS 26.0, *)
extension OpenVoxboardRecordIntent: AudioRecordingIntent, LiveActivityIntent {}

/// Controls retain an explicit per-configuration presentation choice rather
/// than depending on Shortcuts' system execution context. Never expose this
/// dispatcher as a second recording action in the Shortcuts library.
@available(iOS 17.0, *)
struct VoxboardRecordingControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Recording Control"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = true

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Preset")
    var vox: VoxEntity?

    @Parameter(title: "Action", default: .start)
    var recordingAction: RecordingAction

    @Parameter(title: "Open App", default: true)
    var openApp: Bool

    init() {}

    init(vox: VoxEntity?, action: RecordingAction = .start, openApp: Bool = true) {
        self.vox = vox
        self.recordingAction = action
        self.openApp = openApp
    }

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        try await RecordingIntentExecution.perform(vox: vox, action: recordingAction, openApp: openApp)
    }
}

@available(iOS 26.0, *)
extension VoxboardRecordingControlIntent: AudioRecordingIntent, LiveActivityIntent {}

/// One execution path for Shortcuts, both control kinds, and saved legacy
/// toggles. Presentation is chosen by the caller; recorder safety is shared.
@MainActor
enum RecordingIntentExecution {
    static func perform(vox: VoxEntity?, action: RecordingAction, openApp: Bool) async throws -> some IntentResult & OpensIntent {
        guard AppConstants.lockScreenQuickRecordEnabled else { return .result() }
        let foreground = OpenVoxboardRecordingActionIntent(vox: vox, action: action)
        guard #available(iOS 18.2, *) else {
#if VOXBOARD_WIDGET_EXTENSION
            // The legacy foreground flag normally routes execution to the
            // app. Never report a successful recording if old-OS routing
            // unexpectedly executes here instead.
            throw RecordingActionError.openAppRequired
#else
            // Older systems open the app through openAppWhenRun before this
            // method. Queue the handoff without an 18.2-only opensIntent result.
            _ = try await foreground.perform()
            return .result()
#endif
        }
        if openApp { return .result(opensIntent: foreground) }
        guard #available(iOS 26.0, *) else {
            return .result(opensIntent: foreground)
        }
#if VOXBOARD_WIDGET_EXTENSION
        // LiveActivityIntent normally routes to the app process. If the system
        // executes in the extension instead, preserve the requested operation
        // through the foreground handoff, including Stop.
        return .result(opensIntent: foreground)
#else
        let effects = PersistentRecorder.active.map { recorder in
            BackgroundRecordingAction.Effects(
                isRecording: { recorder.isSegmentActive },
                start: { recorder.startOneShotInAppSegment(flowId: $0, origin: .quickRecord) },
                stop: { recorder.stopInAppSegment() },
                stopListening: { recorder.stopListening() },
                ensureLiveActivity: { LiveActivityController.shared.startIfNeeded(reason: .shortcutRecording) },
                endShortcutActivity: { LiveActivityController.shared.endShortcutRecordingActivityIfNeeded() }
            )
        }
        switch BackgroundRecordingAction.perform(action: action, flowID: VoxEntity.requestedFlowID(for: vox), effects: effects) {
        case .completed:
            return .result()
        case .openApp(let fallbackAction):
            return .result(opensIntent: OpenVoxboardRecordingActionIntent(vox: vox, action: fallbackAction))
        }
#endif
    }
}

private enum RecordingActionError: LocalizedError {
    case openAppRequired

    var errorDescription: String? {
        String(localized: "Open Vox.md to run this recording action.")
    }
}

// MARK: - Pending Widget Recording Selection

struct WidgetRecordingFlowSelection {
    let flowID: String
    let explicitlyRequestedFlow: CapturePreset?

    static func persistRequestedFlowID(
        from url: URL,
        defaults: UserDefaults? = AppConstants.sharedDefaults
    ) {
        defaults?.removeObject(forKey: AppConstants.pendingWidgetRecordDraftAttachAudioKey)
        WidgetRecordingActionSelection.persist(.start, defaults: defaults)
        let requestedFlowID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "flowId" })?
            .value
        if let requestedFlowID, !requestedFlowID.isEmpty {
            defaults?.set(requestedFlowID, forKey: AppConstants.pendingWidgetRecordFlowIdKey)
        } else {
            defaults?.removeObject(forKey: AppConstants.pendingWidgetRecordFlowIdKey)
        }
    }

    static func resolve(
        requestedFlowID: String?,
        defaults: UserDefaults? = AppConstants.sharedDefaults
    ) -> WidgetRecordingFlowSelection {
        if let requestedFlowID,
           let flow = CapturePresetStore.flow(id: requestedFlowID, defaults: defaults),
           flow.isEnabled {
            return WidgetRecordingFlowSelection(
                flowID: flow.id,
                explicitlyRequestedFlow: flow
            )
        }

        return WidgetRecordingFlowSelection(
            flowID: CapturePresetStore.selectedFlowId(defaults: defaults),
            explicitlyRequestedFlow: nil
        )
    }
}

// MARK: - Control Configuration Intent

@available(iOS 18.0, *)
struct SelectVoxboardRecordVoxIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Configure Recording"
    static let description = IntentDescription("Choose a Capture Preset, recording action, and whether to open Vox.md.")

    @Parameter(title: "Preset", description: "The Capture Preset to use for recordings started by this control.")
    var vox: VoxEntity?

    // Optional fields preserve configurations saved before these choices
    // existed: Record defaults to Start/Open App; the legacy background control
    // defaults to Start or Stop without opening the app.
    @Parameter(title: "Action", description: "Start, stop, or start/stop recording. Leave unset to keep this control's original behavior.")
    var recordingAction: RecordingAction?

    @Parameter(title: "Open App", description: "Open Vox.md when recording. Background recording requires iOS 26+. Leave unset to keep this control's original behavior.")
    var openApp: Bool?

    static var parameterSummary: some ParameterSummary {
        Summary("Record with \(\.$vox)") {
            \.$recordingAction
            \.$openApp
        }
    }

    init() {}

    init(vox: VoxEntity?, action: RecordingAction? = nil, openApp: Bool? = nil) {
        self.vox = vox
        self.recordingAction = action
        self.openApp = openApp
    }
}
