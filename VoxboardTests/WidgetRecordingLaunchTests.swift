import VoxboardShared
import XCTest
@testable import Voxboard

/// #115: the Lock Screen record control (and the widget) always starts a new
/// recording, without a "Finish the current recording" prompt, whatever an
/// earlier recording or session left behind.
@MainActor
final class WidgetRecordingLaunchTests: XCTestCase {
    // MARK: Foreground launch (control opens the app, widget tap)

    func testStartWithNothingActiveStartsANewRecording() async {
        let launch = LaunchEffects()
        let outcome = await launch.perform(.start)
        XCTAssertEqual(outcome, .started(finishedActiveRecording: false))
        XCTAssertEqual(launch.events, ["load", "start"])
        XCTAssertTrue(launch.isRecording)
    }

    func testControlStartWhileRecordingFinishesAndSavesItThenStartsANewOne() async {
        let launch = LaunchEffects(isRecording: true)
        let outcome = await launch.perform(.start)
        XCTAssertEqual(outcome, .started(finishedActiveRecording: true))
        XCTAssertEqual(launch.events, ["finish", "load", "start"])
        XCTAssertTrue(launch.isRecording)
    }

    func testShortcutStartWhileRecordingKeepsItsDocumentedNoChangeMeaning() async {
        let launch = LaunchEffects(isRecording: true)
        let outcome = await launch.perform(.start, startsNewRecording: false)
        XCTAssertEqual(outcome, .unchanged)
        XCTAssertTrue(launch.events.isEmpty)
        XCTAssertTrue(launch.isRecording)
    }

    func testImmediateStartIgnoresABusyComposerFromAStaleSessionOrEarlierTranscription() async {
        // A recovered queue job from a killed app, an earlier recording still
        // transcribing, or a leftover draft all mark the composer busy. None
        // of them is an active recording.
        let launch = LaunchEffects(composerAvailable: false)
        let outcome = await launch.perform(.start)
        XCTAssertEqual(outcome, .started(finishedActiveRecording: false))
        XCTAssertEqual(launch.events, ["load", "start"])
    }

    func testDraftStartWaitsForEarlierWorkShowsItThenRecordsIntoANewNote() async {
        let launch = LaunchEffects(isRecording: true, composerAvailable: false, plan: .closeOpenNote)
        launch.composerFreesAfterPolls = 50
        let outcome = await launch.perform(.start, isDraft: true)
        XCTAssertEqual(outcome, .started(finishedActiveRecording: true))
        XCTAssertEqual(launch.polls, 50)
        XCTAssertEqual(launch.events, ["finish", "load", "waiting:true", "waiting:false", "newNote", "start"])
    }

    func testDraftDeliveryNeverRecordsOutsideTheDraftWhileTheComposerStaysBusy() async {
        // A composer that never frees (stuck preset switch, a queue job that
        // never releases the route): "Add to Draft" keeps its review step. It
        // records nothing elsewhere and keeps showing that it is waiting until
        // the wait is cancelled or replaced (coordinator tests below).
        let launch = LaunchEffects(isRecording: true, composerAvailable: false, plan: .closeOpenNote)
        launch.cancelsAfterPolls = 3_000
        let outcome = await Task { await launch.perform(.start, isDraft: true) }.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(launch.polls, 3_000)
        XCTAssertEqual(launch.events, ["finish", "load", "waiting:true", "waiting:false"])
        XCTAssertFalse(launch.isRecording)
    }

    func testDraftStartWithAFreeComposerShowsNoWaitingState() async {
        let launch = LaunchEffects(plan: .closeOpenNote)
        let outcome = await launch.perform(.start, isDraft: true)
        XCTAssertEqual(outcome, .started(finishedActiveRecording: false))
        XCTAssertEqual(launch.events, ["load", "newNote", "start"])
    }

    func testCancelledDraftWaitRecordsNothingAndClearsTheWaitingState() async {
        let launch = LaunchEffects(composerAvailable: false, plan: .closeOpenNote)
        launch.cancelsAfterPolls = 3
        let outcome = await Task { await launch.perform(.start, isDraft: true) }.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(launch.events, ["load", "waiting:true", "waiting:false"])
    }

    func testDraftStartOnABlankComposerOrAnUnclosableDraftRecordsWithoutClosingIt() async {
        for plan in [WidgetRecordingLaunch.NewNotePlan.alreadyBlank, .keepDraft] {
            let launch = LaunchEffects(plan: plan)
            let outcome = await launch.perform(.start, isDraft: true)
            XCTAssertEqual(outcome, .started(finishedActiveRecording: false))
            XCTAssertEqual(launch.events, ["load", "start"])
        }
    }

    func testDraftStartKeepsTheOpenNoteWhenItCannotBeClosed() async {
        let launch = LaunchEffects(newNoteAllowed: false, plan: .closeOpenNote)
        let outcome = await launch.perform(.start, isDraft: true)
        XCTAssertEqual(outcome, .notStarted)
        XCTAssertEqual(launch.events, ["load", "newNote"])
    }

    func testNewNotePlanClosesAnyOpenNoteOrUnsavedWordsItCan() {
        XCTAssertEqual(WidgetRecordingLaunch.newNotePlan(hasOpenNote: false, hasContent: false, canCloseIntoNewNote: false), .alreadyBlank)
        XCTAssertEqual(WidgetRecordingLaunch.newNotePlan(hasOpenNote: false, hasContent: false, canCloseIntoNewNote: true), .alreadyBlank)
        XCTAssertEqual(WidgetRecordingLaunch.newNotePlan(hasOpenNote: true, hasContent: false, canCloseIntoNewNote: true), .closeOpenNote)
        XCTAssertEqual(WidgetRecordingLaunch.newNotePlan(hasOpenNote: false, hasContent: true, canCloseIntoNewNote: true), .closeOpenNote)
        // Remote-only Route (closing would Send) or Live Notes off.
        XCTAssertEqual(WidgetRecordingLaunch.newNotePlan(hasOpenNote: false, hasContent: true, canCloseIntoNewNote: false), .keepDraft)
    }

    func testRecordingStartedElsewhereWhileLoadingIsLeftAlone() async {
        let launch = LaunchEffects()
        launch.startsElsewhereDuringLoad = true
        let outcome = await launch.perform(.start)
        XCTAssertEqual(outcome, .unchanged)
        XCTAssertEqual(launch.events, ["load"])
    }

    func testStopAndToggleKeepTheirMeaning() async {
        let idleStop = LaunchEffects()
        let idleStopOutcome = await idleStop.perform(.stop)
        XCTAssertEqual(idleStopOutcome, .unchanged)
        XCTAssertTrue(idleStop.events.isEmpty)

        for action in [RecordingAction.stop, .toggle] {
            let recording = LaunchEffects(isRecording: true)
            let outcome = await recording.perform(action)
            XCTAssertEqual(outcome, .stopped)
            XCTAssertEqual(recording.events, ["finish"])
            XCTAssertFalse(recording.isRecording)
        }

        let idleToggle = LaunchEffects()
        let toggleOutcome = await idleToggle.perform(.toggle)
        XCTAssertEqual(toggleOutcome, .started(finishedActiveRecording: false))
    }

    func testFailedStartIsReported() async {
        let launch = LaunchEffects(startAllowed: false)
        let outcome = await launch.perform(.start)
        XCTAssertEqual(outcome, .notStarted)
    }

    func testImmediateLaunchRecordingNeverWritesIntoTheComposer() {
        // Immediate delivery starts while Send, OCR or an import may own the
        // composer. Its recording must not render live words into, or deliver
        // into, that composer: it previews nowhere and runs from the Route's
        // frozen snapshot, independent of the composer's preset.
        let immediate = RecordingCompletionMode.runVox(flowID: "route")
        XCTAssertFalse(immediate.previewsLiveTranscriptInComposer(commandOrigin: .quickRecord))
        XCTAssertFalse(immediate.blocksCapturePresetSelectionDuringProcessing)
        XCTAssertNil(RecordingCompletionMode.voiceProcessingConfiguration(for: immediate, selectedPreset: nil))
        if case .preset = immediate.recordingJobDelivery {} else { XCTFail("Immediate delivery must use the Preset job") }
        // Draft delivery does write into the composer, which is why it waits.
        XCTAssertTrue(RecordingCompletionMode.captureDraft(attachAudio: false)
            .previewsLiveTranscriptInComposer(commandOrigin: .quickRecord))
    }

    // MARK: Duplicate deliveries of one press

    func testCopyArrivingWhileALaunchIsStartingIsDropped() async {
        let coordinator = WidgetRecordingLaunchCoordinator()
        let launch = LaunchEffects()
        let first = coordinator.launch(action: .start, isDraftDelivery: false, startsNewRecording: true, effects: launch.effects)
        let copy = coordinator.launch(action: .start, isDraftDelivery: false, startsNewRecording: true, effects: launch.effects)
        XCTAssertNotNil(first)
        XCTAssertNil(copy)
        let outcome = await first?.value
        XCTAssertEqual(outcome, .started(finishedActiveRecording: false))
        XCTAssertEqual(launch.events, ["load", "start"])
        XCTAssertFalse(coordinator.isBusy)
    }

    func testStopBehindAStartingLaunchRunsAfterItInsteadOfBeingDropped() async {
        let coordinator = WidgetRecordingLaunchCoordinator(now: { Date(timeIntervalSince1970: 1_000) })
        let launch = LaunchEffects()
        let start = coordinator.launch(action: .start, isDraftDelivery: false, startsNewRecording: true, effects: launch.effects)
        let stop = coordinator.launch(action: .stop, isDraftDelivery: false, startsNewRecording: true, effects: launch.effects)
        XCTAssertNotNil(stop, "Stop is not a copy of Start")
        let startOutcome = await start?.value
        let stopOutcome = await stop?.value
        XCTAssertEqual(startOutcome, .started(finishedActiveRecording: false))
        XCTAssertEqual(stopOutcome, .stopped)
        XCTAssertEqual(launch.events, ["load", "start", "finish"])
        XCTAssertFalse(launch.isRecording)
        XCTAssertFalse(coordinator.isBusy)
    }

    func testToggleBehindAStartingLaunchStopsTheNewRecording() async {
        let coordinator = WidgetRecordingLaunchCoordinator()
        let launch = LaunchEffects()
        let start = coordinator.launch(action: .start, isDraftDelivery: false, startsNewRecording: true, effects: launch.effects)
        let toggle = coordinator.launch(action: .toggle, isDraftDelivery: false, startsNewRecording: true, effects: launch.effects)
        _ = await start?.value
        let outcome = await toggle?.value
        XCTAssertEqual(outcome, .stopped)
        XCTAssertFalse(launch.isRecording)
    }

    func testNewPressReplacesALaunchWaitingForTheComposer() async {
        let coordinator = WidgetRecordingLaunchCoordinator()
        let waiting = LaunchEffects(composerAvailable: false, plan: .closeOpenNote)
        waiting.sleepsForReal = true
        let first = coordinator.launch(action: .start, isDraftDelivery: true, startsNewRecording: true, effects: waiting.effects)
        for _ in 0..<200 where !coordinator.isWaitingForComposer { await Task.yield() }
        XCTAssertTrue(coordinator.isWaitingForComposer)

        let next = LaunchEffects()
        let second = coordinator.launch(action: .start, isDraftDelivery: false, startsNewRecording: true, effects: next.effects)
        XCTAssertNotNil(second, "A press behind a wait is never silently dropped")
        let firstOutcome = await first?.value
        let secondOutcome = await second?.value
        XCTAssertEqual(firstOutcome, .cancelled)
        XCTAssertEqual(waiting.events.last, "waiting:false")
        XCTAssertFalse(waiting.events.contains("start"))
        XCTAssertEqual(secondOutcome, .started(finishedActiveRecording: false))
        XCTAssertFalse(coordinator.isBusy)
    }

    func testCancelEndsAWaitingLaunchAndFreesTheCoordinator() async {
        let coordinator = WidgetRecordingLaunchCoordinator()
        let waiting = LaunchEffects(composerAvailable: false, plan: .closeOpenNote)
        waiting.sleepsForReal = true
        let first = coordinator.launch(action: .start, isDraftDelivery: true, startsNewRecording: true, effects: waiting.effects)
        for _ in 0..<200 where !coordinator.isWaitingForComposer { await Task.yield() }
        coordinator.cancel()
        let outcome = await first?.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertFalse(coordinator.isBusy)
        XCTAssertFalse(coordinator.isWaitingForComposer)

        let later = LaunchEffects()
        let next = await coordinator.launch(action: .start, isDraftDelivery: false, startsNewRecording: true, effects: later.effects)?.value
        XCTAssertEqual(next, .started(finishedActiveRecording: false))
    }

    func testRunRefusesASecondLaunchWhileOneIsInFlight() async {
        let coordinator = WidgetRecordingLaunchCoordinator()
        let launch = LaunchEffects(composerAvailable: false, plan: .alreadyBlank)
        launch.composerFreesAfterPolls = 5
        let first = Task { await coordinator.run(action: .start, isDraftDelivery: true, startsNewRecording: true, effects: launch.effects) }
        for _ in 0..<100 where !coordinator.isInFlight { await Task.yield() }
        XCTAssertTrue(coordinator.isInFlight)
        let copy = await coordinator.run(action: .start, isDraftDelivery: true, startsNewRecording: true, effects: launch.effects)
        XCTAssertNil(copy)
        let firstOutcome = await first.value
        XCTAssertEqual(firstOutcome, .started(finishedActiveRecording: false))
        XCTAssertFalse(coordinator.isInFlight)
        XCTAssertEqual(launch.events.filter { $0 == "start" }.count, 1)
    }

    func testCopyArrivingRightAfterTheStartDoesNotSplitTheRecording() async {
        var clock = Date(timeIntervalSince1970: 1_000)
        let coordinator = WidgetRecordingLaunchCoordinator(now: { clock })
        let launch = LaunchEffects()
        let first = await coordinator.run(action: .start, isDraftDelivery: false, startsNewRecording: true, effects: launch.effects)
        XCTAssertEqual(first, .started(finishedActiveRecording: false))

        clock += WidgetRecordingLaunchCoordinator.duplicateWindow - 0.5
        let copy = await coordinator.run(action: .start, isDraftDelivery: false, startsNewRecording: true, effects: launch.effects)
        XCTAssertEqual(copy, .unchanged)
        XCTAssertEqual(launch.events, ["load", "start"])
        XCTAssertTrue(launch.isRecording)
    }

    func testPressAfterTheDuplicateWindowStartsANewRecording() async {
        var clock = Date(timeIntervalSince1970: 1_000)
        let coordinator = WidgetRecordingLaunchCoordinator(now: { clock })
        let launch = LaunchEffects()
        _ = await coordinator.run(action: .start, isDraftDelivery: false, startsNewRecording: true, effects: launch.effects)

        clock += WidgetRecordingLaunchCoordinator.duplicateWindow + 0.5
        let second = await coordinator.run(action: .start, isDraftDelivery: false, startsNewRecording: true, effects: launch.effects)
        XCTAssertEqual(second, .started(finishedActiveRecording: true))
        XCTAssertEqual(launch.events, ["load", "start", "finish", "load", "start"])
    }

    func testDuplicateWindowOnlyCoversRecordingsALaunchStarted() async {
        // An in-app recording that is already running is finished at once.
        let coordinator = WidgetRecordingLaunchCoordinator()
        let launch = LaunchEffects(isRecording: true)
        let outcome = await coordinator.run(action: .start, isDraftDelivery: false, startsNewRecording: true, effects: launch.effects)
        XCTAssertEqual(outcome, .started(finishedActiveRecording: true))
    }

    // MARK: Background control (Open App off)

    func testBackgroundControlStartWhileRecordingSavesItAndStartsANewOne() {
        let recording = BackgroundEffects(isRecording: true)
        let outcome = BackgroundRecordingAction.perform(action: .start, flowID: "preset", startsNewRecording: true, effects: recording.effects)
        XCTAssertEqual(outcome, .completed)
        // The status card is confirmed before anything is stopped.
        XCTAssertEqual(recording.events, ["activity", "stop", "start:preset", "activity"])
        XCTAssertTrue(recording.isRecording)
    }

    func testBackgroundControlRestartWithoutAStatusCardKeepsRecordingAndLetsTheAppRestart() {
        // Nothing is stopped in the background, so there is never a moment
        // with no recording. The app opens with Start and the press is still
        // marked, so it finishes and restarts in one step there.
        let recording = BackgroundEffects(isRecording: true, activityAllowed: false)
        let outcome = BackgroundRecordingAction.perform(action: .start, flowID: "preset", startsNewRecording: true, effects: recording.effects)
        XCTAssertEqual(outcome, .openApp(action: .start))
        XCTAssertEqual(recording.events, ["activity"])
        XCTAssertTrue(recording.isRecording)
    }

    func testForegroundHandoffAfterABackgroundRestartFinishesAndStartsInOneStep() async {
        let launch = LaunchEffects(isRecording: true)
        let outcome = await launch.perform(.start, startsNewRecording: true)
        XCTAssertEqual(outcome, .started(finishedActiveRecording: true))
        XCTAssertEqual(launch.events, ["finish", "load", "start"])
    }

    func testBackgroundShortcutStartWhileRecordingStillLeavesItUnchanged() {
        let recording = BackgroundEffects(isRecording: true)
        let outcome = BackgroundRecordingAction.perform(action: .start, flowID: "preset", effects: recording.effects)
        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(recording.events, ["activity"])
    }

    func testForegroundFallbackAfterAShortcutCouldNotShowItsCardLeavesTheRecordingAlone() async {
        // BackgroundRecordingAction's `.none` fallback opens the app with
        // Start for a Shortcut. That launch is not a control press.
        let launch = LaunchEffects(isRecording: true)
        let outcome = await launch.perform(.start, startsNewRecording: false)
        XCTAssertEqual(outcome, .unchanged)
        XCTAssertTrue(launch.isRecording)
    }

    // MARK: Who asked for a new recording

    func testControlsAndWidgetMarkTheirLaunchAndShortcutsClearIt() async throws {
        let defaults = try XCTUnwrap(AppConstants.sharedDefaults)
        let keys = [AppConstants.lockScreenQuickRecordEnabledKey, AppConstants.pendingWidgetRecordKey,
                    AppConstants.pendingWidgetRecordFlowIdKey, WidgetRecordingActionSelection.key,
                    AppConstants.pendingWidgetRecordDraftAttachAudioKey,
                    PendingQuickRecordingRequest.startsNewRecordingKey]
        let originals = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, originals) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(true, forKey: AppConstants.lockScreenQuickRecordEnabledKey)
        let preset = VoxEntity.fallback

        // Lock Screen / Control Center control that opens the app.
        _ = try await VoxboardRecordingControlIntent(vox: preset, action: .start, openApp: true).perform()
        _ = try await OpenVoxboardRecordingActionIntent(vox: preset, action: .start).perform()
        var request = PendingQuickRecordingRequest.consume(defaults: defaults)
        XCTAssertTrue(request.startsNewRecording)
        XCTAssertNil(defaults.object(forKey: PendingQuickRecordingRequest.startsNewRecordingKey), "Consumed once")

        // A Shortcut run afterwards must not inherit a control's leftover mark.
        PendingQuickRecordingRequest.markStartsNewRecording(true, defaults: defaults)
        _ = try await RecordingIntentExecution.perform(vox: preset, action: .start, openApp: true)
        _ = try await OpenVoxboardRecordingActionIntent(vox: preset, action: .start).perform()
        request = PendingQuickRecordingRequest.consume(defaults: defaults)
        XCTAssertFalse(request.startsNewRecording)

        // A control handled in the background (Open App off) clears its own
        // mark: nothing in the foreground will consume it.
        PendingQuickRecordingRequest.markStartsNewRecording(true, defaults: defaults)
        _ = try await VoxboardRecordingControlIntent(vox: preset, action: .stop, openApp: false).perform()
        XCTAssertNil(defaults.object(forKey: PendingQuickRecordingRequest.startsNewRecordingKey))

        // A mark the app never consumed (it was never brought up) expires,
        // so a much later launch can't inherit it and finish a recording.
        let pressedAt = Date()
        PendingQuickRecordingRequest.markStartsNewRecording(true, defaults: defaults, now: pressedAt)
        _ = try await OpenVoxboardRecordingActionIntent(vox: preset, action: .start).perform()
        request = PendingQuickRecordingRequest.consume(
            defaults: defaults,
            now: pressedAt.addingTimeInterval(PendingQuickRecordingRequest.startsNewRecordingLifetime + 1)
        )
        XCTAssertFalse(request.startsNewRecording)
        XCTAssertNil(defaults.object(forKey: PendingQuickRecordingRequest.startsNewRecordingKey))
        PendingQuickRecordingRequest.markStartsNewRecording(true, defaults: defaults, now: pressedAt)
        _ = try await OpenVoxboardRecordingActionIntent(vox: preset, action: .start).perform()
        request = PendingQuickRecordingRequest.consume(defaults: defaults, now: pressedAt.addingTimeInterval(5))
        XCTAssertTrue(request.startsNewRecording)

        // Home Screen widget tap (voxboard://widget-record).
        WidgetRecordingFlowSelection.persistRequestedFlowID(
            from: try XCTUnwrap(URL(string: "voxboard://widget-record")),
            defaults: defaults
        )
        request = PendingQuickRecordingRequest.consume(defaults: defaults)
        XCTAssertTrue(request.startsNewRecording)
        XCTAssertEqual(request.recordingAction, .start)
    }
}

@MainActor
private final class LaunchEffects {
    var isRecording: Bool
    var composerAvailable: Bool
    var newNoteAllowed: Bool
    var startAllowed: Bool
    var plan: WidgetRecordingLaunch.NewNotePlan
    var composerFreesAfterPolls: Int?
    var cancelsAfterPolls: Int?
    /// Real poll sleeps, for tests that cancel or replace a waiting launch
    /// before the wait limit runs out.
    var sleepsForReal = false
    var startsElsewhereDuringLoad = false
    var polls = 0
    var events: [String] = []

    init(
        isRecording: Bool = false,
        composerAvailable: Bool = true,
        newNoteAllowed: Bool = true,
        startAllowed: Bool = true,
        plan: WidgetRecordingLaunch.NewNotePlan = .alreadyBlank
    ) {
        self.isRecording = isRecording
        self.composerAvailable = composerAvailable
        self.newNoteAllowed = newNoteAllowed
        self.startAllowed = startAllowed
        self.plan = plan
    }

    func perform(
        _ action: RecordingAction,
        isDraft: Bool = false,
        startsNewRecording: Bool = true
    ) async -> WidgetRecordingLaunch.Outcome {
        await WidgetRecordingLaunch.perform(
            action: action,
            isDraftDelivery: isDraft,
            startsNewRecording: startsNewRecording,
            effects: effects
        )
    }

    var effects: WidgetRecordingLaunch.Effects {
        WidgetRecordingLaunch.Effects(
            isRecording: { self.isRecording },
            finishActiveRecording: {
                self.events.append("finish")
                self.isRecording = false
            },
            loadComposer: {
                self.events.append("load")
                if self.startsElsewhereDuringLoad { self.isRecording = true }
            },
            isComposerAvailable: { self.composerAvailable },
            setWaitingForComposer: { self.events.append("waiting:\($0)") },
            newNotePlan: { self.plan },
            prepareNewNote: {
                self.events.append("newNote")
                return self.newNoteAllowed
            },
            start: {
                self.events.append("start")
                guard self.startAllowed else { return false }
                self.isRecording = true
                return true
            },
            sleep: { interval in
                if self.sleepsForReal {
                    self.polls += 1
                    try? await Task.sleep(for: interval)
                    return
                }
                self.polls += 1
                if let cancelAt = self.cancelsAfterPolls, self.polls >= cancelAt {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
                if let freeAt = self.composerFreesAfterPolls, self.polls >= freeAt {
                    self.composerAvailable = true
                }
                await Task.yield()
            }
        )
    }
}

@MainActor
private final class BackgroundEffects {
    var isRecording: Bool
    let activityAllowed: Bool
    var events: [String] = []

    init(isRecording: Bool = false, activityAllowed: Bool = true) {
        self.isRecording = isRecording
        self.activityAllowed = activityAllowed
    }

    var effects: BackgroundRecordingAction.Effects {
        BackgroundRecordingAction.Effects(
            isRecording: { self.isRecording },
            start: { flowID in
                self.events.append("start:\(flowID ?? "nil")")
                self.isRecording = true
                return true
            },
            stop: {
                self.events.append("stop")
                self.isRecording = false
            },
            stopListening: {
                self.events.append("stopListening")
                self.isRecording = false
            },
            ensureLiveActivity: {
                self.events.append("activity")
                return self.activityAllowed
            },
            endShortcutActivity: { self.events.append("endActivity") }
        )
    }
}
