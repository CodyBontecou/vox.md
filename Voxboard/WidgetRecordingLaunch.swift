import Foundation

/// Runs a pending Lock Screen control / widget / Record Audio launch in the
/// foreground app, without ever asking the user to "finish the current
/// recording" (#115).
///
/// A control or widget press means "record a new note", like the in-app
/// Record new note button (`startsNewRecording`):
/// - A recording that is still active is finished and saved first (it keeps
///   its own Route and completion mode), then the new recording starts.
/// - Immediate delivery runs from the recorder's frozen Route snapshot and
///   never touches the composer, so earlier transcription, a recovered queue
///   job from a killed app, or a leftover draft does not block it.
/// - Draft delivery records into the composer. It waits, for as long as it
///   takes, until earlier work on the composer is done (the caller shows that
///   it is waiting), then opens a blank note and starts.
///
/// A Shortcut's Start keeps its documented meaning: an active recording is
/// left unchanged.
///
/// Effects are injected so tests can cover the flow without a microphone.
@MainActor
enum WidgetRecordingLaunch {
    enum Outcome: Equatable {
        case started(finishedActiveRecording: Bool)
        case stopped
        case unchanged
        /// Draft delivery only: the launch was cancelled while waiting for
        /// the composer. Nothing was recorded and nothing is shown.
        case cancelled
        case notStarted
    }

    /// How a draft launch gets a new note once the composer is free.
    enum NewNotePlan: Equatable {
        /// The composer is already a blank, unbound note.
        case alreadyBlank
        /// Close the open note like New note, then record into a blank one.
        case closeOpenNote
        /// The draft can't be closed into a note without sending it (a
        /// Remote-only Route, or Live Notes off where the draft is the note).
        /// Record into it; nothing is sent and nothing is lost.
        case keepDraft
    }

    static func newNotePlan(hasOpenNote: Bool, hasContent: Bool, canCloseIntoNewNote: Bool) -> NewNotePlan {
        guard hasOpenNote || hasContent else { return .alreadyBlank }
        return canCloseIntoNewNote ? .closeOpenNote : .keepDraft
    }

    struct Effects {
        var isRecording: () -> Bool
        /// True while the active recording is the one an earlier launch
        /// started moments ago (the same press delivered twice).
        var isRecentLaunchRecording: () -> Bool = { false }
        /// Finish and save the active recording.
        var finishActiveRecording: () -> Void
        var loadComposer: () async -> Void
        var isComposerAvailable: () -> Bool
        /// Draft delivery is waiting for earlier composer work (`true`) or has
        /// stopped waiting (`false`).
        var setWaitingForComposer: (Bool) -> Void = { _ in }
        var newNotePlan: () -> NewNotePlan
        /// Close the open note like New note; `false` keeps it and records nothing.
        var prepareNewNote: () async -> Bool
        var start: () -> Bool
        var sleep: (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    }

    static let composerPollInterval: Duration = .milliseconds(100)

    static func perform(
        action: RecordingAction,
        isDraftDelivery isDraft: Bool,
        startsNewRecording: Bool,
        effects: Effects
    ) async -> Outcome {
        var finishedActiveRecording = false
        if effects.isRecording() {
            switch action {
            case .stop, .toggle:
                effects.finishActiveRecording()
                return .stopped
            case .start:
                guard startsNewRecording, !effects.isRecentLaunchRecording() else { return .unchanged }
                effects.finishActiveRecording()
                finishedActiveRecording = true
            }
        } else if action == .stop {
            return .unchanged
        }

        await effects.loadComposer()
        if isDraft {
            guard await waitForComposer(effects) else { return .cancelled }
            switch effects.newNotePlan() {
            case .alreadyBlank, .keepDraft:
                break
            case .closeOpenNote:
                guard await effects.prepareNewNote() else { return .notStarted }
            }
        }
        // Another start (in-app Speak, the keyboard) may have begun while the
        // composer loaded. Leave that recording alone.
        guard !effects.isRecording() else { return .unchanged }
        guard effects.start() else { return .notStarted }
        return .started(finishedActiveRecording: finishedActiveRecording)
    }

    private static func waitForComposer(_ effects: Effects) async -> Bool {
        guard !effects.isComposerAvailable() else { return true }
        effects.setWaitingForComposer(true)
        defer { effects.setWaitingForComposer(false) }
        while !effects.isComposerAvailable() {
            guard !Task.isCancelled else { return false }
            await effects.sleep(composerPollInterval)
        }
        return !Task.isCancelled
    }
}

/// Serializes launches for the composer: the same press can reach the app
/// more than once (launch flag, notification, scene activation). A copy that
/// arrives while a launch is in flight is dropped instead of racing it, and a
/// copy that arrives within `duplicateWindow` of the recording a launch just
/// started is treated as the same press rather than as "start another one".
@MainActor
final class WidgetRecordingLaunchCoordinator {
    static let duplicateWindow: TimeInterval = 2

    private(set) var isInFlight = false
    private var lastStartedAt: Date?
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// `nil` when the launch was dropped as a copy of one in flight.
    func run(
        action: RecordingAction,
        isDraftDelivery: Bool,
        startsNewRecording: Bool,
        effects: WidgetRecordingLaunch.Effects
    ) async -> WidgetRecordingLaunch.Outcome? {
        guard !isInFlight else { return nil }
        isInFlight = true
        defer { isInFlight = false }

        var effects = effects
        effects.isRecentLaunchRecording = { [weak self] in
            guard let self, let startedAt = self.lastStartedAt else { return false }
            return self.now().timeIntervalSince(startedAt) < Self.duplicateWindow
        }
        let outcome = await WidgetRecordingLaunch.perform(
            action: action,
            isDraftDelivery: isDraftDelivery,
            startsNewRecording: startsNewRecording,
            effects: effects
        )
        if case .started = outcome { lastStartedAt = now() }
        return outcome
    }
}
