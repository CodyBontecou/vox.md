import Foundation
import os.log
import VoxboardCaptureCore
import VoxboardShared
import WidgetKit

#if canImport(ActivityKit)
import ActivityKit
#endif

private let osLog = Logger(subsystem: "bontecou.Voxboard", category: "LiveActivity")

/// Why a Live Activity is currently presented. Each reason is guarded by its
/// own Vox.md setting so the always-on monitor card and the card shown while
/// an App Intent toggle recording (Shortcuts, Apple Pencil squeeze, Action
/// Button) is running can be enabled independently.
enum LiveActivityPresentationReason {
    /// The always-on listening monitor card with Record/Stop controls.
    case monitor
    /// The card shown while a recording is toggled in place without opening
    /// the app, so the user sees elapsed time and can stop from the Lock
    /// Screen or Dynamic Island.
    case shortcutRecording

    var isAllowed: Bool {
        switch self {
        case .monitor:
            return AppConstants.liveActivityMonitorEnabled
        case .shortcutRecording:
            return AppConstants.shortcutRecordingLiveActivityEnabled
        }
    }
}

/// Read-only snapshot of the recorder's active segment used to decorate the
/// Live Activity with its route, pause clock, and Pause availability.
struct LiveActivitySegmentContext {
    let requestId: String?
    let flow: CapturePreset?
    let isPaused: Bool
    let canPause: Bool
    /// Wall-clock start minus already-recorded time.
    let effectiveStartedAt: TimeInterval
    /// Recorded time excluding pauses.
    let elapsed: TimeInterval
}

/// Owns the lock-screen / Dynamic Island Live Activity for Voxboard.
///
/// Lifecycle:
/// - `startIfNeeded()` when the always-on recorder becomes active.
/// - `update(isSegmentActive:isTranscribing:startedAt:)` whenever a segment starts, stops, or begins processing.
/// - `end()` when the recorder stops listening entirely.
///
/// All calls are no-ops on pre-iOS 16.1 devices or when Live Activities are
/// disabled in Settings.
@MainActor
final class LiveActivityController {

    static let shared = LiveActivityController()

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private var activity: Activity<VoxboardActivityAttributes>? {
        get { _activity as? Activity<VoxboardActivityAttributes> }
        set { _activity = newValue }
    }
    private var _activity: Any?
    private var endingActivityIDs: Set<String> = []
    private var activityMutationTask: Task<Void, Never>?
    private var desiredState = VoxboardLiveActivityState.idle
    private var shouldStartAfterPendingEnd = false
    /// Last failure reason from `startIfNeeded`, for diagnostics.
    private(set) var lastStartFailureDescription: String?
    /// Why the currently tracked activity was started. Preserved when an
    /// existing activity is reused so a monitor card is never re-gated by the
    /// shortcut-recording setting or vice versa.
    private var presentationReason: LiveActivityPresentationReason = .monitor

    // Route context for the displayed segment.
    private var routeRequestID: String?
    private var routeName: String?
    private var routeMonogram: String?
    private var destinationPath: String?
    private var destinationTask: Task<Void, Never>?

    // Waveform + pause sampling. Levels are bucketed (peak per bucket) and
    // pushed to ActivityKit at most once per `pushInterval` to respect the
    // system's update budget while keeping the bars visibly live.
    private var levelSampler: Timer?
    private var levelHistory: [UInt8] = []
    private var bucketPeak: Float = 0
    private var lastBucketAt: TimeInterval = 0
    private var lastPushAt: TimeInterval = 0
    private var levelsDirty = false
    private var lastPausedState: Bool?
    private static let sampleInterval: TimeInterval = 0.15
    private static let bucketInterval: TimeInterval = 0.5
    private static let pushInterval: TimeInterval = 1.0
    #endif

    private init() {}

    /// Starts (or reuses) the presentation. Returns true when an activity is
    /// tracked after the call — either reused (e.g. the listening monitor) or
    /// newly requested. Callers that must guarantee a card — audio recording
    /// intents fatally assert when their session is active without one — use
    /// the result to decide whether background recording may begin.
    @discardableResult
    func startIfNeeded(reason newReason: LiveActivityPresentationReason = .monitor) -> Bool {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return false }

        // An existing presentation can always be reused regardless of the
        // incoming reason's setting.
        let existingActivities = Activity<VoxboardActivityAttributes>.activities
            .filter { !endingActivityIDs.contains($0.id) }
        let trackedID = activity?.id
        let primaryActivity = trackedID.flatMap { id in
            existingActivities.first(where: { $0.id == id })
        } ?? existingActivities.first

        if let primaryActivity {
            activity = primaryActivity

            let duplicates = existingActivities.filter { $0.id != primaryActivity.id }
            endActivities(duplicates)
            enqueueUpdate(primaryActivity, state: desiredState)
            osLog.notice("Reusing Live Activity; dismissed \(duplicates.count) duplicate(s)")
            return true
        }

        guard newReason.isAllowed else {
            if presentationReason == newReason {
                end()
            }
            lastStartFailureDescription = "setting disabled: \(newReason)"
            osLog.notice("Live Activity for \(String(describing: newReason), privacy: .public) disabled in Voxboard settings — skipping start")
            return false
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            end()
            lastStartFailureDescription = "live activities disabled (system or app setting)"
            osLog.notice("Live Activities disabled — skipping start")
            return false
        }

        // ActivityKit ends asynchronously. Wait before requesting the replacement
        // so a launch with several orphaned cards cannot exceed the activity limit.
        if !endingActivityIDs.isEmpty {
            if !shouldStartAfterPendingEnd {
                shouldStartAfterPendingEnd = true
                enqueueActivityMutation { [weak self] in
                    guard let self, self.shouldStartAfterPendingEnd else { return }
                    self.shouldStartAfterPendingEnd = false
                    _ = self.startIfNeeded(reason: newReason)
                }
            }
            lastStartFailureDescription = "pending end of previous activity"
            return false
        }
        shouldStartAfterPendingEnd = false

        let state = desiredState
        do {
            // Background-started presentations (shortcut recordings) must use
            // the transient style — requesting a standard activity from the
            // background fails with ActivityAuthorizationError.visibility.
            // Transient cards present in the Dynamic Island without the
            // foreground visibility requirement and auto-expire.
            let style: ActivityStyle = newReason == .shortcutRecording ? .transient : .standard
            if #available(iOS 18.0, *) {
                let content = ActivityContent(state: state, staleDate: nil)
                activity = try Activity.request(
                    attributes: VoxboardActivityAttributes(),
                    content: content,
                    pushType: nil,
                    style: style
                )
            } else if #available(iOS 16.2, *) {
                let content = ActivityContent(state: state, staleDate: nil)
                activity = try Activity.request(
                    attributes: VoxboardActivityAttributes(),
                    content: content,
                    pushType: nil
                )
            } else {
                activity = try Activity.request(
                    attributes: VoxboardActivityAttributes(),
                    contentState: state,
                    pushType: nil
                )
            }
            presentationReason = newReason
            lastStartFailureDescription = nil
            osLog.notice("Started Live Activity")
            return true
        } catch {
            lastStartFailureDescription = String(describing: error)
            osLog.error("Failed to start Live Activity: \(String(describing: error))")
            return false
        }
        #else
        return false
        #endif
    }

    func update(
        isSegmentActive: Bool,
        isTranscribing: Bool = false,
        startedAt: TimeInterval?,
        requestId: String? = nil,
        transcriptionProgress: Double? = nil
    ) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        let wasTranscribing = desiredState.isTranscribing || desiredState.isSegmentActive
        let base = VoxboardLiveActivityState(
            isSegmentActive: isSegmentActive,
            isTranscribing: isTranscribing,
            segmentStartedAt: isSegmentActive ? startedAt : nil,
            segmentRequestId: isSegmentActive ? requestId : nil,
            transcriptionProgress: isTranscribing ? transcriptionProgress : nil
        )
        if isSegmentActive {
            prepareRouteContext(requestId: requestId)
            startLevelSampler()
        } else {
            stopLevelSampler()
            if !isTranscribing { clearRouteContext() }
        }
        if wasTranscribing, !isSegmentActive, !isTranscribing {
            reloadRouteWidgets()
        }
        let state = decorated(base)
        desiredState = state
        guard presentationReason.isAllowed else {
            end()
            return
        }
        guard let activity else { return }
        enqueueUpdate(activity, state: state)
        #endif
    }

    /// End every activity owned by Vox.md, not only the in-memory reference.
    /// ActivityKit can preserve activities across process termination, so ending
    /// the complete collection prevents stacked Lock Screen/Dynamic Island cards.
    func end() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }

        var activities = Activity<VoxboardActivityAttributes>.activities
        if let tracked = activity,
           !activities.contains(where: { $0.id == tracked.id }) {
            activities.append(tracked)
        }
        activity = nil
        desiredState = .idle
        stopLevelSampler()
        clearRouteContext()
        shouldStartAfterPendingEnd = false
        presentationReason = .monitor
        endActivities(activities)
        if !activities.isEmpty {
            osLog.notice("Ending \(activities.count) Live Activity instance(s)")
        }
        #endif
    }

    /// End the Live Activity only when it is currently presented for a
    /// shortcut-triggered toggle recording. Monitor presentations — owned by
    /// the always-on listening setting — are left untouched.
    func endShortcutRecordingActivityIfNeeded() {
        guard presentationReason == .shortcutRecording else { return }
        end()
    }

    /// Re-reads pause/clock state from the recorder and pushes it immediately.
    /// Called by the Pause/Resume intent so the card reflects the tap at once.
    func refreshRecordingState() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard desiredState.isSegmentActive else { return }
        lastPausedState = PersistentRecorder.active?.liveActivitySegmentContext?.isPaused
        pushDecoratedState()
        #endif
    }

    #if canImport(ActivityKit)
    // MARK: - Route context

    private func prepareRouteContext(requestId: String?) {
        guard routeRequestID != requestId || routeRequestID == nil else { return }
        routeRequestID = requestId
        levelHistory = []
        bucketPeak = 0
        levelsDirty = false
        lastPausedState = nil
        destinationTask?.cancel()
        destinationPath = nil

        let flow = PersistentRecorder.active?.liveActivitySegmentContext?.flow
        routeName = flow?.visibleName
        routeMonogram = VoxboardLiveActivityState.monogram(name: flow?.visibleName, emoji: flow?.emoji)
        guard let flow else { return }
        destinationTask = Task { @MainActor [weak self] in
            let path = await Self.resolveDestinationPath(flow: flow)
            guard let self, !Task.isCancelled, self.routeRequestID == requestId, let path else { return }
            self.destinationPath = path
            self.pushDecoratedState()
        }
    }

    private func clearRouteContext() {
        destinationTask?.cancel()
        destinationTask = nil
        routeRequestID = nil
        routeName = nil
        routeMonogram = nil
        destinationPath = nil
        levelHistory = []
    }

    /// Preview of where this segment will land, e.g. `Meetings/2026-11-01.md`.
    /// Uses the same route precedence as delivery; nil for legacy exports.
    private static func resolveDestinationPath(flow: CapturePreset) async -> String? {
        guard let destinationID = await ConfiguredTranscriptCaptureDestinationExporter
                .resolvedDestinationID(flow: flow),
              let root = AppConstants.captureDirectoryURL else { return nil }
        let store = CaptureLibraryStore(
            fileURL: root.appendingPathComponent(CaptureLibraryStore.defaultFilename)
        )
        guard let library = try? await store.load(),
              let destination = library.destinations.first(where: { $0.id == destinationID }) else {
            return nil
        }
        let request = CaptureRequest(
            source: .voice,
            destinationID: destinationID,
            payloads: [],
            voxProfile: flow.captureProfile
        )
        if let path = try? CapturePathPlanner().relativePath(for: request, destination: destination) {
            return path
        }
        let name = destination.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func decorated(_ base: VoxboardLiveActivityState) -> VoxboardLiveActivityState {
        var state = base
        guard base.isSegmentActive || base.isTranscribing else { return state }
        state.routeName = routeName
        state.routeMonogram = routeMonogram
        state.destinationPath = destinationPath
        guard base.isSegmentActive else { return state }
        if let context = PersistentRecorder.active?.liveActivitySegmentContext,
           context.requestId == nil || context.requestId == base.segmentRequestId {
            state.segmentStartedAt = context.effectiveStartedAt
            state.pausedElapsed = context.isPaused ? context.elapsed : nil
            state.canPause = context.canPause
        }
        state.audioLevels = levelHistory.isEmpty ? nil : levelHistory
        return state
    }

    private func pushDecoratedState() {
        guard #available(iOS 16.1, *) else { return }
        let state = decorated(desiredState)
        desiredState = state
        lastPushAt = Date().timeIntervalSince1970
        levelsDirty = false
        guard presentationReason.isAllowed, let activity else { return }
        enqueueUpdate(activity, state: state)
    }

    // MARK: - Level sampling

    private func startLevelSampler() {
        guard levelSampler == nil else { return }
        let now = Date().timeIntervalSince1970
        lastBucketAt = now
        lastPushAt = now
        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { _ in
            Task { @MainActor in LiveActivityController.shared.sampleLevel() }
        }
        levelSampler = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopLevelSampler() {
        levelSampler?.invalidate()
        levelSampler = nil
        bucketPeak = 0
        levelsDirty = false
    }

    private func sampleLevel() {
        guard desiredState.isSegmentActive else {
            stopLevelSampler()
            return
        }
        let context = PersistentRecorder.active?.liveActivitySegmentContext
        let paused = context?.isPaused ?? false
        if let lastPausedState, lastPausedState != paused {
            self.lastPausedState = paused
            pushDecoratedState()
            return
        }
        lastPausedState = paused

        let now = Date().timeIntervalSince1970
        if !paused {
            bucketPeak = max(bucketPeak, TranscriptionIPC.readAudioLevel() ?? 0)
            if now - lastBucketAt >= Self.bucketInterval {
                levelHistory.append(VoxboardLiveActivityState.encodedLevel(bucketPeak))
                if levelHistory.count > VoxboardLiveActivityState.maximumAudioLevelCount {
                    levelHistory.removeFirst(levelHistory.count - VoxboardLiveActivityState.maximumAudioLevelCount)
                }
                bucketPeak = 0
                lastBucketAt = now
                levelsDirty = true
            }
        } else {
            lastBucketAt = now
        }
        if levelsDirty, now - lastPushAt >= Self.pushInterval {
            pushDecoratedState()
        }
    }

    private func reloadRouteWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: VoxboardRouteWidgetKinds.today)
        // Delivery can land shortly after processing ends; refresh once more.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            WidgetCenter.shared.reloadTimelines(ofKind: VoxboardRouteWidgetKinds.today)
        }
    }

    @available(iOS 16.1, *)
    private func enqueueUpdate(
        _ activity: Activity<VoxboardActivityAttributes>,
        state: VoxboardLiveActivityState
    ) {
        enqueueActivityMutation {
            if #available(iOS 16.2, *) {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            } else {
                await activity.update(using: state)
            }
        }
    }

    @available(iOS 16.1, *)
    private func endActivities(_ activities: [Activity<VoxboardActivityAttributes>]) {
        let candidates = activities.filter { !endingActivityIDs.contains($0.id) }
        guard !candidates.isEmpty else { return }

        let ids = Set(candidates.map(\.id))
        endingActivityIDs.formUnion(ids)
        enqueueActivityMutation { [weak self] in
            for activity in candidates {
                if #available(iOS 16.2, *) {
                    await activity.end(
                        ActivityContent(state: .idle, staleDate: nil),
                        dismissalPolicy: .immediate
                    )
                } else {
                    await activity.end(using: .idle, dismissalPolicy: .immediate)
                }
            }
            self?.endingActivityIDs.subtract(ids)
        }
    }

    @available(iOS 16.1, *)
    private func enqueueActivityMutation(
        _ mutation: @escaping @MainActor () async -> Void
    ) {
        let previousTask = activityMutationTask
        activityMutationTask = Task { @MainActor in
            await previousTask?.value
            await mutation()
        }
    }
    #endif
}
