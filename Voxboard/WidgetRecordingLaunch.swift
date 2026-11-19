import Foundation

/// Runs a pending Lock Screen control / widget / Record Audio launch in the
/// foreground app. Start means "record a new note", the same as the in-app
/// Record new note button, so a launch never asks the user to finish anything:
///
/// - A recording that is still active is finished and saved first (it keeps
///   its own Route and completion mode), then the new recording starts.
/// - Immediate delivery runs from the recorder's frozen Route snapshot and
///   never touches the composer, so earlier transcription, a recovered queue
///   job from a killed app, or a leftover draft does not block it.
/// - Draft delivery records into the composer, so it waits briefly for earlier
///   work on the composer to settle and then opens a blank note.
/// - A second launch delivered for the same press (duplicate notification,
///   scene activation) is ignored instead of finishing the recording that the
///   first launch just started.
///
/// Effects are injected so tests can cover the flow without a microphone.
@MainActor
enum WidgetRecordingLaunch {
    enum Outcome: Equatable {
        case started(finishedActiveRecording: Bool)
        case stopped
        case unchanged
        /// Draft delivery only: the composer stayed busy past the wait.
        case composerBusy
        case notStarted
    }

    struct Effects {
        var isRecording: () -> Bool
        /// True while the active recording is the one an earlier launch
        /// started moments ago (the same press delivered twice).
        var isRecentLaunchRecording: () -> Bool
        /// Finish and save the active recording.
        var finishActiveRecording: () -> Void
        var loadComposer: () async -> Void
        var isComposerAvailable: () -> Bool
        /// Close the open note like New note; `false` keeps it and records nothing.
        var prepareNewNote: () async -> Bool
        var start: () -> Bool
        var sleep: (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    }

    static let composerWaitTimeout: Duration = .seconds(20)
    static let composerPollInterval: Duration = .milliseconds(100)

    static func perform(
        action: RecordingAction,
        isDraftDelivery isDraft: Bool,
        effects: Effects
    ) async -> Outcome {
        var finishedActiveRecording = false
        if effects.isRecording() {
            switch action {
            case .stop, .toggle:
                effects.finishActiveRecording()
                return .stopped
            case .start:
                if effects.isRecentLaunchRecording() { return .unchanged }
                effects.finishActiveRecording()
                finishedActiveRecording = true
            }
        } else if action == .stop {
            return .unchanged
        }

        await effects.loadComposer()
        if isDraft {
            guard await waitForComposer(effects) else { return .composerBusy }
            guard await effects.prepareNewNote() else { return .notStarted }
        }
        // Another start (in-app Speak, the keyboard) may have begun while the
        // composer loaded. Leave that recording alone.
        guard !effects.isRecording() else { return .unchanged }
        guard effects.start() else { return .notStarted }
        return .started(finishedActiveRecording: finishedActiveRecording)
    }

    private static func waitForComposer(_ effects: Effects) async -> Bool {
        var waited: Duration = .zero
        while !effects.isComposerAvailable() {
            guard waited < composerWaitTimeout, !Task.isCancelled else { return false }
            await effects.sleep(composerPollInterval)
            waited += composerPollInterval
        }
        return true
    }
}
