import XCTest
@testable import Voxboard

/// #115: the Lock Screen record control (and widget / Record Audio launches)
/// always starts a new recording, without a "Finish the current recording"
/// prompt, whatever an earlier recording or session left behind.
@MainActor
final class WidgetRecordingLaunchTests: XCTestCase {
    func testStartWithNothingActiveStartsANewRecording() async {
        let launch = LaunchEffects()
        let outcome = await WidgetRecordingLaunch.perform(action: .start, isDraftDelivery: false, effects: launch.effects)
        XCTAssertEqual(outcome, .started(finishedActiveRecording: false))
        XCTAssertEqual(launch.events, ["load", "start"])
        XCTAssertTrue(launch.isRecording)
    }

    func testStartWhileRecordingFinishesAndSavesItThenStartsANewOne() async {
        let launch = LaunchEffects(isRecording: true)
        let outcome = await WidgetRecordingLaunch.perform(action: .start, isDraftDelivery: false, effects: launch.effects)
        XCTAssertEqual(outcome, .started(finishedActiveRecording: true))
        XCTAssertEqual(launch.events, ["finish", "load", "start"])
        XCTAssertTrue(launch.isRecording)
    }

    func testImmediateStartIgnoresABusyComposerFromAStaleSessionOrEarlierTranscription() async {
        // A recovered queue job from a killed app, an earlier recording still
        // transcribing, or a leftover draft all mark the composer busy. None
        // of them is an active recording.
        let launch = LaunchEffects(composerAvailable: false)
        let outcome = await WidgetRecordingLaunch.perform(action: .start, isDraftDelivery: false, effects: launch.effects)
        XCTAssertEqual(outcome, .started(finishedActiveRecording: false))
        XCTAssertEqual(launch.events, ["load", "start"])
    }

    func testDraftStartWaitsForEarlierWorkThenRecordsIntoANewNote() async {
        let launch = LaunchEffects(isRecording: true, composerAvailable: false)
        launch.composerFreesAfterPolls = 3
        let outcome = await WidgetRecordingLaunch.perform(action: .start, isDraftDelivery: true, effects: launch.effects)
        XCTAssertEqual(outcome, .started(finishedActiveRecording: true))
        XCTAssertEqual(launch.events, ["finish", "load", "sleep", "sleep", "sleep", "newNote", "start"])
    }

    func testDraftStartGivesUpWhenTheComposerStaysBusy() async {
        let launch = LaunchEffects(composerAvailable: false)
        let outcome = await WidgetRecordingLaunch.perform(action: .start, isDraftDelivery: true, effects: launch.effects)
        XCTAssertEqual(outcome, .composerBusy)
        XCTAssertFalse(launch.events.contains("start"))
        XCTAssertFalse(launch.events.contains("newNote"))
    }

    func testDraftStartKeepsTheOpenNoteWhenItCannotBeClosed() async {
        let launch = LaunchEffects(newNoteAllowed: false)
        let outcome = await WidgetRecordingLaunch.perform(action: .start, isDraftDelivery: true, effects: launch.effects)
        XCTAssertEqual(outcome, .notStarted)
        XCTAssertEqual(launch.events, ["load", "newNote"])
    }

    func testDuplicateDeliveryOfTheSamePressDoesNotSplitTheRecording() async {
        let launch = LaunchEffects(isRecording: true, recentLaunchRecording: true)
        let outcome = await WidgetRecordingLaunch.perform(action: .start, isDraftDelivery: false, effects: launch.effects)
        XCTAssertEqual(outcome, .unchanged)
        XCTAssertTrue(launch.events.isEmpty)
        XCTAssertTrue(launch.isRecording)
    }

    func testRecordingStartedElsewhereWhileLoadingIsLeftAlone() async {
        let launch = LaunchEffects()
        launch.startsElsewhereDuringLoad = true
        let outcome = await WidgetRecordingLaunch.perform(action: .start, isDraftDelivery: false, effects: launch.effects)
        XCTAssertEqual(outcome, .unchanged)
        XCTAssertEqual(launch.events, ["load"])
    }

    func testStopAndToggleKeepTheirMeaning() async {
        let idleStop = LaunchEffects()
        let idleStopOutcome = await WidgetRecordingLaunch.perform(action: .stop, isDraftDelivery: false, effects: idleStop.effects)
        XCTAssertEqual(idleStopOutcome, .unchanged)
        XCTAssertTrue(idleStop.events.isEmpty)

        for action in [RecordingAction.stop, .toggle] {
            let recording = LaunchEffects(isRecording: true)
            let outcome = await WidgetRecordingLaunch.perform(action: action, isDraftDelivery: false, effects: recording.effects)
            XCTAssertEqual(outcome, .stopped)
            XCTAssertEqual(recording.events, ["finish"])
            XCTAssertFalse(recording.isRecording)
        }

        let idleToggle = LaunchEffects()
        let toggleOutcome = await WidgetRecordingLaunch.perform(action: .toggle, isDraftDelivery: false, effects: idleToggle.effects)
        XCTAssertEqual(toggleOutcome, .started(finishedActiveRecording: false))
    }

    func testFailedStartIsReported() async {
        let launch = LaunchEffects(startAllowed: false)
        let outcome = await WidgetRecordingLaunch.perform(action: .start, isDraftDelivery: false, effects: launch.effects)
        XCTAssertEqual(outcome, .notStarted)
    }
}

@MainActor
private final class LaunchEffects {
    var isRecording: Bool
    var recentLaunchRecording: Bool
    var composerAvailable: Bool
    var newNoteAllowed: Bool
    var startAllowed: Bool
    var composerFreesAfterPolls: Int?
    var startsElsewhereDuringLoad = false
    var events: [String] = []

    init(
        isRecording: Bool = false,
        recentLaunchRecording: Bool = false,
        composerAvailable: Bool = true,
        newNoteAllowed: Bool = true,
        startAllowed: Bool = true
    ) {
        self.isRecording = isRecording
        self.recentLaunchRecording = recentLaunchRecording
        self.composerAvailable = composerAvailable
        self.newNoteAllowed = newNoteAllowed
        self.startAllowed = startAllowed
    }

    var effects: WidgetRecordingLaunch.Effects {
        WidgetRecordingLaunch.Effects(
            isRecording: { self.isRecording },
            isRecentLaunchRecording: { self.recentLaunchRecording },
            finishActiveRecording: {
                self.events.append("finish")
                self.isRecording = false
            },
            loadComposer: {
                self.events.append("load")
                if self.startsElsewhereDuringLoad { self.isRecording = true }
            },
            isComposerAvailable: { self.composerAvailable },
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
            sleep: { _ in
                // Only the tests that count polls record them; the busy-forever
                // case would otherwise log 200 entries.
                guard let remaining = self.composerFreesAfterPolls else { return }
                self.events.append("sleep")
                if remaining <= 1 {
                    self.composerAvailable = true
                    self.composerFreesAfterPolls = nil
                } else {
                    self.composerFreesAfterPolls = remaining - 1
                }
            }
        )
    }
}
