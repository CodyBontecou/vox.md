import KeyboardKit
import SwiftUI
import UIKit
import VoxboardShared

private typealias S = KeyboardSignal

/// Host-document operations the pad performs. Supplied by the controller so the
/// views never hold the `UITextDocumentProxy` directly.
struct KeyboardTextActions {
    var insert: (String) -> Void
}

// MARK: - Voice pad (Signal "Voice keyboard" board)

/// Voice-first keyboard: destination toggle + timer, the Route's pinned quick
/// actions, a live transcript line, a large mic/stop control flanked by
/// Delete last phrase and Return, and next keyboard / space / ABC.
struct VoicePadView: View {
    @Bindable var voiceState: VoiceKeyboardState
    let hasFullAccess: Bool
    let text: KeyboardTextActions
    let showLetters: () -> Void

    @State private var isPickingRoute = false
    @State private var location = KeyboardQuickActions.LocationRequester()
    @State private var actionError: String?

    var body: some View {
        VStack(spacing: 12) {
            VoiceHeaderRow(voiceState: voiceState, isPickingRoute: $isPickingRoute)

            if isPickingRoute {
                RoutePickerRow(voiceState: voiceState) { isPickingRoute = false }
            } else {
                QuickActionsRow(
                    voiceState: voiceState,
                    location: location,
                    onError: showActionError
                )
            }

            TranscriptPreviewLine(
                voiceState: voiceState,
                hasFullAccess: hasFullAccess,
                actionError: actionError
            )

            HStack(spacing: 20) {
                CircleKey(systemImage: "delete.left", label: String(localized: "Delete last phrase")) {
                    KeyboardHaptics.tap()
                    voiceState.deleteLastPhrase()
                }
                MicControl(voiceState: voiceState, hasFullAccess: hasFullAccess)
                CircleKey(systemImage: "return", label: String(localized: "Insert return")) {
                    KeyboardHaptics.tap()
                    text.insert("\n")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                NextKeyboardKey()
                Button {
                    KeyboardHaptics.tap()
                    text.insert(" ")
                } label: {
                    Text("space")
                        .font(S.sans(14))
                        .foregroundStyle(S.secondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(S.key, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(KeyPressStyle())
                .accessibilityLabel(Text("Space"))

                Button {
                    KeyboardHaptics.tap()
                    showLetters()
                } label: {
                    Text(verbatim: "ABC")
                        .font(S.sans(14, weight: .semibold))
                        .foregroundStyle(S.ink)
                        .frame(width: 64, height: 40)
                        .background(S.key, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(KeyPressStyle())
                .accessibilityLabel(Text("Letter keyboard"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        // Board: 384pt section = 12pt top + 342pt content + 30pt home
        // indicator. The system draws the home-indicator strip below the
        // extension, so the pad keeps 342pt of content (a 144pt mic area that
        // fits the 140pt recording rings) plus 12/8pt insets.
        .frame(height: 362)
        .animation(.easeInOut(duration: 0.18), value: isPickingRoute)
        .onDisappear { location.cancel() }
    }

    private func showActionError(_ message: String) {
        actionError = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if actionError == message { actionError = nil }
        }
    }
}

// MARK: - Letter keyboard chrome

/// Slim bar above the KeyboardKit letter keyboard: back to voice + the same
/// pinned quick actions.
struct LetterModeBar: View {
    @Bindable var voiceState: VoiceKeyboardState
    let showVoice: () -> Void

    @State private var location = KeyboardQuickActions.LocationRequester()

    var body: some View {
        HStack(spacing: 8) {
            Button {
                KeyboardHaptics.tap()
                showVoice()
            } label: {
                HStack(spacing: 6) {
                    if voiceState.status == .recording {
                        Circle().fill(S.red).frame(width: 7, height: 7)
                        Text(formatDuration(voiceState.recordingDuration))
                            .font(S.mono(12.5))
                            .monospacedDigit()
                            .foregroundStyle(S.red)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(S.ink)
                    }
                }
                .padding(.horizontal, 10)
                .frame(minWidth: 40, minHeight: 32)
                .background(S.key, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(KeyPressStyle())
            .accessibilityLabel(Text("Voice keyboard"))

            QuickActionsRow(voiceState: voiceState, location: location, onError: { _ in })
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .onDisappear { location.cancel() }
    }
}

// MARK: - Header: destination + timer

private struct VoiceHeaderRow: View {
    @Bindable var voiceState: VoiceKeyboardState
    @Binding var isPickingRoute: Bool
    @State private var modelChangeCount = 0

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                segment(
                    title: Text("Type here"),
                    isOn: voiceState.destination == .typeHere,
                    showsChevron: false
                ) {
                    voiceState.destination = .typeHere
                    isPickingRoute = false
                }
                segment(
                    title: Text("Send to \(voiceState.currentFlow.accessibilityName)"),
                    isOn: voiceState.destination == .route,
                    showsChevron: voiceState.destination == .route
                ) {
                    voiceState.refreshFlowCache()
                    if voiceState.destination == .route {
                        // Second tap on the selected segment opens the Route picker.
                        isPickingRoute.toggle()
                    } else {
                        voiceState.destination = .route
                    }
                }
            }
            .padding(3)
            .background(S.key, in: Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Destination"))
            .layoutPriority(1)

            Spacer(minLength: 0)

            statusBadge
        }
        .onChange(of: modelChangeCount) {
            KeyboardHaptics.selection()
        }
    }

    private func segment(
        title: Text,
        isOn: Bool,
        showsChevron: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            KeyboardHaptics.selection()
            action()
        } label: {
            HStack(spacing: 4) {
                title
                    .lineLimit(1)
                    .truncationMode(.tail)
                if showsChevron {
                    Image(systemName: isPickingRoute ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .font(S.sans(13, weight: isOn ? .semibold : .medium))
            .foregroundStyle(isOn ? S.inkOnLight : S.secondary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(isOn ? S.ink : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch voiceState.status {
        case .recording:
            Text(verbatim: "● " + formatDuration(voiceState.recordingDuration))
                .font(S.mono(11.5))
                .monospacedDigit()
                .foregroundStyle(S.red)
                .accessibilityLabel(Text("Recording \(formatDuration(voiceState.recordingDuration))"))
        case .transcribing:
            Text(transcriptionLabel)
                .font(S.mono(11.5))
                .monospacedDigit()
                .foregroundStyle(S.muted)
                .lineLimit(1)
        default:
            // Unobtrusive model picker: tap cycles the downloaded backends.
            Button {
                voiceState.nextModel()
                modelChangeCount += 1
            } label: {
                Text(voiceState.currentModelName)
                    .font(S.mono(11.5))
                    .foregroundStyle(S.muted)
                    .lineLimit(1)
                    .frame(minHeight: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Transcription model: \(voiceState.currentModelName)"))
            .accessibilityHint(Text("Switches to the next downloaded model"))
        }
    }

    private var transcriptionLabel: String {
        guard let progress = voiceState.transcriptionProgress, progress.isFinite else {
            return String(localized: "Transcribing…")
        }
        let whole = Int((min(1, max(0, progress)) * 100).rounded(.down))
        return "\(whole)%"
    }
}

// MARK: - Route picker

private struct RoutePickerRow: View {
    @Bindable var voiceState: VoiceKeyboardState
    let dismiss: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(voiceState.enabledFlows) { flow in
                    let isOn = flow.id == voiceState.currentFlow.id
                    Button {
                        KeyboardHaptics.selection()
                        voiceState.selectFlow(id: flow.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Text(flow.shortLabel)
                                .font(S.mono(10.5, medium: true))
                                .foregroundStyle(isOn ? S.ink : S.inkOnLight)
                                .frame(minWidth: 20, minHeight: 20)
                                .padding(.horizontal, 2)
                                .background(isOn ? S.inkOnLight : S.secondary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Text(flow.accessibilityName)
                                .font(S.sans(13, weight: isOn ? .semibold : .medium))
                                .foregroundStyle(isOn ? S.inkOnLight : S.ink)
                                .lineLimit(1)
                        }
                        .padding(.leading, 6)
                        .padding(.trailing, 10)
                        .frame(height: 32)
                        .background(isOn ? S.ink : S.key, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(KeyPressStyle())
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
        .frame(height: 32)
        .accessibilityLabel(Text("Route"))
    }
}

// MARK: - Quick actions

private struct QuickActionsRow: View {
    @Bindable var voiceState: VoiceKeyboardState
    let location: KeyboardQuickActions.LocationRequester
    let onError: (String) -> Void

    var body: some View {
        let pins = KeyboardQuickActions.pins(forRoute: voiceState.currentFlow.id)
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    TimelineView(.everyMinute) { context in
                        HStack(spacing: 6) {
                            ForEach(pins) { action in
                                chip(action, now: context.date)
                            }
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Quick actions"))

            Text("\(voiceState.currentFlow.accessibilityName) pins")
                .font(S.sans(11.5))
                .foregroundStyle(S.muted)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: 32)
    }

    private func chip(_ action: CaptureQuickAction, now: Date) -> some View {
        Button {
            KeyboardHaptics.tap()
            perform(action)
        } label: {
            Group {
                if action == .currentLocation, location.isRequesting {
                    ProgressView().scaleEffect(0.6).tint(S.ink)
                } else {
                    Text(verbatim: KeyboardQuickActions.glyph(for: action, now: now))
                        .font(S.mono(12.5))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(S.ink)
            .padding(.horizontal, 9)
            .frame(minWidth: 32, minHeight: 32)
            .background(S.key, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(Text(verbatim: action.defaultLabel))
    }

    private func perform(_ action: CaptureQuickAction) {
        if action == .currentLocation {
            location.requestMarkdown { result in
                switch result {
                case .success(let markdown):
                    voiceState.insertSnippet(markdown)
                case .failure:
                    onError(String(localized: "Location unavailable — allow it for Vox.md in Settings"))
                }
            }
            return
        }
        guard let snippet = KeyboardQuickActions.snippet(for: action) else {
            if action == .paste { onError(String(localized: "Nothing to paste")) }
            return
        }
        voiceState.insertSnippet(snippet.text, cursorOffset: snippet.cursorOffset)
    }
}

// MARK: - Live transcript line

private struct TranscriptPreviewLine: View {
    @Bindable var voiceState: VoiceKeyboardState
    let hasFullAccess: Bool
    let actionError: String?

    var body: some View {
        content
            .font(S.sans(15, relativeTo: .subheadline))
            .lineSpacing(15 * 0.4 - 4)
            .lineLimit(2, reservesSpace: false)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        if let actionError {
            Text(actionError).foregroundStyle(S.red)
        } else {
            switch voiceState.status {
            case .recording, .transcribing:
                livePreview
            case .error(let message):
                Text(message).foregroundStyle(S.red)
            case .needsFullAccess:
                Text("Allow Full Access for Vox.md in Settings › Keyboards to dictate.")
                    .foregroundStyle(S.red)
            case .noModel:
                Text("Open Vox.md to prepare transcription.")
                    .foregroundStyle(S.red)
            case .appNotListening:
                Text("Tap the mic to open Vox.md and start listening.")
                    .foregroundStyle(S.muted)
            case .idle:
                if let confirmation = voiceState.confirmationMessage {
                    Text(confirmation).foregroundStyle(S.ink)
                } else if !hasFullAccess {
                    Text("Allow Full Access for Vox.md in Settings › Keyboards to dictate.")
                        .foregroundStyle(S.muted)
                } else if voiceState.destination == .route {
                    Text("Tap the mic — your words go to \(voiceState.currentFlow.accessibilityName).")
                        .foregroundStyle(S.faint)
                } else {
                    Text("Tap the mic and speak — words appear here as you talk.")
                        .foregroundStyle(S.faint)
                }
            }
        }
    }

    /// Committed tail in muted ink, the revisable volatile tail fainter with an
    /// ellipsis — "and the updated presets list…".
    private var livePreview: Text {
        let committed = Self.tail(voiceState.livePreviewCommittedText, limit: 90)
        let volatile = (voiceState.volatileTranscription ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if committed.isEmpty, volatile.isEmpty {
            let placeholder = voiceState.status == .transcribing
                ? String(localized: "Transcribing…")
                : String(localized: "Listening…")
            return Text(placeholder).foregroundColor(S.faint)
        }
        var line = Text(committed).foregroundColor(S.muted)
        if !volatile.isEmpty {
            let separator = committed.isEmpty || committed.hasSuffix(" ") ? "" : " "
            line = line + Text(verbatim: separator + volatile + "…").foregroundColor(S.faint)
        }
        return line
    }

    private static func tail(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .newlines)
        guard trimmed.count > limit else { return trimmed }
        let suffix = trimmed.suffix(limit)
        if let space = suffix.firstIndex(of: " ") {
            return String(suffix[suffix.index(after: space)...])
        }
        return String(suffix)
    }
}

// MARK: - Mic control

private struct MicControl: View {
    @Bindable var voiceState: VoiceKeyboardState
    let hasFullAccess: Bool

    var body: some View {
        Button(action: tap) {
            ZStack {
                switch voiceState.status {
                case .recording:
                    Circle().fill(S.red)
                    micGlyph(.white)
                case .transcribing:
                    Circle().fill(S.key)
                    if let progress = voiceState.transcriptionProgress, progress.isFinite {
                        Circle()
                            .trim(from: 0, to: min(1, max(0, progress)))
                            .stroke(S.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(6)
                    }
                    ProgressView().tint(S.ink).scaleEffect(1.2)
                case .appNotListening, .noModel, .needsFullAccess:
                    Circle().fill(S.key)
                    micGlyph(S.muted)
                default:
                    Circle().fill(S.red)
                    micGlyph(.white)
                }
            }
            .frame(width: 96, height: 96)
            .background {
                if voiceState.status == .recording {
                    let level = CGFloat(voiceState.audioLevels.last ?? 0)
                    ZStack {
                        Circle().fill(S.red.opacity(0.08))
                            .frame(width: 140 + level * 8, height: 140 + level * 8)
                        Circle().fill(S.red.opacity(0.18))
                            .frame(width: 116, height: 116)
                    }
                    .animation(.easeOut(duration: 0.1), value: level)
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(KeyPressStyle(scale: 0.96))
        .disabled(voiceState.status == .transcribing)
        .accessibilityLabel(Text(accessibilityLabel))
        .onChange(of: voiceState.status) { old, new in
            if new == .recording || new == .transcribing {
                KeyboardHaptics.impact()
            } else if old == .transcribing, case .idle = new {
                KeyboardHaptics.success()
            } else if case .error = new {
                KeyboardHaptics.error()
            }
        }
    }

    private func micGlyph(_ color: Color) -> some View {
        Image(systemName: "mic")
            .font(.system(size: 32, weight: .medium))
            .foregroundStyle(color)
    }

    private var accessibilityLabel: String {
        switch voiceState.status {
        case .recording: String(localized: "Stop dictation")
        case .transcribing: String(localized: "Transcribing")
        case .appNotListening, .noModel: String(localized: "Open Vox.md")
        default: String(localized: "Start dictation")
        }
    }

    private func tap() {
        switch voiceState.status {
        case .recording:
            voiceState.stopRecording()
        case .transcribing:
            break
        case .appNotListening, .noModel:
            voiceState.openApp(hasFullAccess: hasFullAccess)
        default:
            voiceState.startRecording(hasFullAccess: hasFullAccess)
        }
    }
}

// MARK: - Keys

private struct CircleKey: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(S.ink)
                .frame(width: 52, height: 52)
                .background(S.key, in: Circle())
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(Text(label))
    }
}

private struct NextKeyboardKey: View {
    var body: some View {
        Keyboard.NextKeyboardButton {
            Image(systemName: "globe")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(S.ink)
                .frame(width: 44, height: 40)
                .background(S.key, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .accessibilityLabel(Text("Next keyboard"))
    }
}

private struct KeyPressStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Helpers

enum KeyboardHaptics {
    static func tap() {
        guard AppConstants.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func selection() {
        guard AppConstants.hapticsEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func impact() {
        guard AppConstants.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        guard AppConstants.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        guard AppConstants.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

func formatDuration(_ duration: TimeInterval) -> String {
    let seconds = max(0, Int(duration))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}
