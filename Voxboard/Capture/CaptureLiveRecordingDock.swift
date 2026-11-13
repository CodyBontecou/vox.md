import SwiftUI
import UIKit

/// Phone recording controls that take over the Capture footer while a
/// tap-to-record session runs. The bottom panel (quick actions + Attach /
/// Speak / Send) transforms into this dark dock, and the words stream straight
/// into the editor above at the writer's cursor, so there is no separate
/// transcript surface. Presentation only: the coordinator owns the recorder.
struct CaptureLiveRecordingDock: View {
    let engineLabel: String
    var errorMessage: String? = nil
    let duration: String
    let isPaused: Bool
    let levels: [Float]
    @Binding var isDraftMode: Bool
    let canSnapWhiteboard: Bool
    let discard: () -> Void
    let stop: () -> Void
    let togglePause: () -> Void
    let markMoment: () -> Void
    let addTask: () -> Void
    let snapWhiteboard: () -> Void
    var isKeyboardVisible = false
    var dismissKeyboard: () -> Void = {}
    /// Live Notes: where the words are going (replaces the Draft/Send toggle).
    var liveNoteLine: String? = nil
    var liveNoteLineIsLive = false

    @State private var confirmsDiscard = false
    @State private var actionFeedback: String?

    private static let ink = Color(captureHex: 0xF4F4F1)
    private static let muted = Color(captureHex: 0x9A9A95)
    private static let raised = Color(captureHex: 0x1C1C1C)

    var body: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(Geist.caption())
                    .foregroundStyle(Self.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Geist.recording.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("capture_live_recording_error")
            }
            statusRow
            if let liveNoteLine {
                LiveNoteRecordingLineView(text: liveNoteLine, isLive: liveNoteLineIsLive)
            }
            controls
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Color(captureHex: 0x0B0B0B), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .foregroundStyle(Self.ink)
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .top) {
            if let actionFeedback {
                Text(verbatim: actionFeedback)
                    .font(Geist.caption(.caption))
                    .foregroundStyle(Color(captureHex: 0x0B0B0B))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Self.ink, in: Capsule())
                    .offset(y: -36)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, Geist.Spacing.four)
        .padding(.top, Geist.Spacing.three)
        .padding(.bottom, Geist.Spacing.two)
        // Keep the screen awake while a recording is visible.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .confirmationDialog(
            String(localized: "Discard this recording?"),
            isPresented: $confirmsDiscard,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Discard Recording"), role: .destructive, action: discard)
            Button(String(localized: "Keep Recording"), role: .cancel) {}
        } message: {
            Text("The audio and live transcript are deleted. Nothing is sent.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture_live_recording_dock")
    }

    private var statusRow: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(isPaused ? Self.muted : Geist.recording)
                    .frame(width: 9, height: 9)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                Text(verbatim: duration)
                    .font(.custom("GeistMono-Medium", size: 20, relativeTo: .title3))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .fixedSize()
            .padding(.leading, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(isPaused
                ? String(localized: "Paused, \(duration)")
                : String(localized: "Recording, \(duration)")))
            .accessibilityHint(Text(verbatim: engineLabel))
            if liveNoteLine == nil {
                CaptureRecordingModeSegment(isDraft: $isDraftMode, isLocked: false)
            } else {
                Spacer(minLength: 0)
            }
            if isKeyboardVisible {
                Button(action: dismissKeyboard) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityLabel(Text("Hide keyboard"))
                }
                .buttonStyle(SignalCircleButtonStyle(diameter: 44, filled: Self.raised))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityIdentifier("capture_recording_hide_keyboard")
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                confirmsDiscard = true
            } label: {
                Image(systemName: "xmark")
                    .accessibilityLabel(Text("Discard recording"))
            }
            .buttonStyle(SignalCircleButtonStyle(diameter: 44, filled: Self.raised))
            .accessibilityIdentifier("capture_recording_discard")

            CaptureLiveRecordingWaveform(levels: levels, isPaused: isPaused)
                .frame(height: 32)

            Menu {
                Button {
                    markMoment()
                    flash(String(localized: "Moment marked at \(duration)"))
                } label: {
                    Label(String(localized: "Mark moment"), systemImage: "bookmark")
                }
                .accessibilityIdentifier("capture_recording_mark_moment")
                Button {
                    addTask()
                    flash(String(localized: "Task added to draft"))
                } label: {
                    Label(String(localized: "Add task"), systemImage: "checklist")
                }
                .accessibilityIdentifier("capture_recording_add_task")
                Button(action: snapWhiteboard) {
                    Label(String(localized: "Snap whiteboard"), systemImage: "camera")
                }
                .disabled(!canSnapWhiteboard)
                .accessibilityIdentifier("capture_recording_snap_whiteboard")
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Self.ink)
                    .frame(width: 44, height: 44)
                    .background(Self.raised, in: Circle())
                    .contentShape(Circle())
                    .accessibilityLabel(Text("Recording actions"))
            }
            .accessibilityIdentifier("capture_recording_actions")

            Button(action: togglePause) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .accessibilityLabel(Text(isPaused ? "Resume recording" : "Pause recording"))
            }
            .buttonStyle(SignalCircleButtonStyle(
                diameter: 44,
                filled: isPaused ? Geist.accent : Self.raised
            ))
            .accessibilityIdentifier("capture_recording_pause_toggle")

            Button(action: stop) {
                CaptureStopRingLabel(diameter: 52)
                    .accessibilityLabel(Text(isDraftMode ? "Stop and add to draft" : "Stop and send"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("capture_recording_stop_send")
        }
    }

    private func flash(_ message: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIAccessibility.post(notification: .announcement, argument: message)
        withAnimation(.easeOut(duration: 0.15)) { actionFeedback = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard actionFeedback == message else { return }
            withAnimation(.easeIn(duration: 0.2)) { actionFeedback = nil }
        }
    }
}
