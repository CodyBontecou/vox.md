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
/// - Draft delivery records into the composer. It waits until earlier work
///   on the composer is done (the caller shows that it is waiting), then
///   opens a blank note and starts. It never records outside the draft, so
///   "Add to Draft" always keeps its review step, and it never falls back to
///   the "Finish the current recording…" prompt. The wait ends when the
///   caller cancels it (app backgrounded, Capture closed) or a newer press
///   replaces it (`WidgetRecordingLaunchCoordinator`).
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

    /// `false` when the launch was cancelled while waiting.
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
/// more than once (launch flag, notification, scene activation).
///
/// - A copy that arrives while a launch is starting is dropped instead of
///   racing it.
/// - A press that arrives while a draft launch is waiting for the composer
///   replaces it: the waiting launch is cancelled and the newest press runs.
///   Nothing is silently swallowed behind a wait.
/// - A press within `duplicateWindow` of the recording a launch just started
///   is treated as the same press, not as "start another one". The new
///   recording is already on screen, so a quick double press shows one
///   recording rather than a two-second clip and a second recording.
/// - `cancel()` ends a waiting launch (scene background, view gone), so the
///   coordinator can never stay busy and drop every later press.
@MainActor
final class WidgetRecordingLaunchCoordinator {
    static let duplicateWindow: TimeInterval = 2

    private(set) var isInFlight = false
    private(set) var isWaitingForComposer = false
    private var lastStartedAt: Date?
    private var current: (id: UUID, task: Task<WidgetRecordingLaunch.Outcome?, Never>)?
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// A launch is starting or waiting.
    var isBusy: Bool { current != nil || isInFlight }

    /// Starts a launch, unless it is a copy of one that is already starting
    /// (then `nil`). A launch that is only waiting for the composer is
    /// replaced by this one.
    @discardableResult
    func launch(
        action: RecordingAction,
        isDraftDelivery: Bool,
        startsNewRecording: Bool,
        effects: WidgetRecordingLaunch.Effects
    ) -> Task<WidgetRecordingLaunch.Outcome?, Never>? {
        if let current {
            guard isWaitingForComposer else { return nil }
            current.task.cancel()
        }
        let previous = current?.task
        let id = UUID()
        let task = Task { @MainActor [weak self] () -> WidgetRecordingLaunch.Outcome? in
            // Let the replaced launch unwind (it clears its waiting state).
            _ = await previous?.value
            guard let self else { return nil }
            defer { if self.current?.id == id { self.current = nil } }
            return await self.run(
                action: action,
                isDraftDelivery: isDraftDelivery,
                startsNewRecording: startsNewRecording,
                effects: effects
            )
        }
        current = (id, task)
        return task
    }

    /// Ends a waiting launch without recording.
    func cancel() {
        current?.task.cancel()
    }

    /// Runs one launch now; `nil` when another one is in flight.
    func run(
        action: RecordingAction,
        isDraftDelivery: Bool,
        startsNewRecording: Bool,
        effects: WidgetRecordingLaunch.Effects
    ) async -> WidgetRecordingLaunch.Outcome? {
        guard !isInFlight else { return nil }
        isInFlight = true
        defer {
            isInFlight = false
            isWaitingForComposer = false
        }

        var effects = effects
        effects.isRecentLaunchRecording = { [weak self] in
            guard let self, let startedAt = self.lastStartedAt else { return false }
            return self.now().timeIntervalSince(startedAt) < Self.duplicateWindow
        }
        let showWaiting = effects.setWaitingForComposer
        effects.setWaitingForComposer = { [weak self] isWaiting in
            self?.isWaitingForComposer = isWaiting
            showWaiting(isWaiting)
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
