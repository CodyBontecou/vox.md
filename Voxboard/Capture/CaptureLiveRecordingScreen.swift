import SwiftUI
import UIKit
import VoxboardShared

/// Full-screen dark live recording surface (Signal "Live recording" and
/// "Recording actions" artboards). Presentation only: the coordinator owns the
/// recorder commands, the draft and the camera.
struct CaptureLiveRecordingScreen: View {
    let routeName: String
    let routeSymbolName: String
    let routeEmoji: String?
    /// Route-order tile tone, so the header tile matches the route's letter
    /// tile on the Capture and Routes screens.
    var routeTone: SignalRouteTileTone = .primary
    let engineLabel: String
    var errorMessage: String? = nil
    let speakerCount: Int
    let duration: String
    let isPaused: Bool
    let levels: [Float]
    let lines: [CaptureLiveTranscriptLine]
    let volatileText: String
    let showsSpeakerLabels: Bool
    @Binding var isDraftMode: Bool
    let isModeLocked: Bool
    /// Live Notes: where the words are going (replaces the Draft/Send toggle).
    var liveNoteLine: String? = nil
    var liveNoteLineIsLive = false
    let canSnapWhiteboard: Bool
    let discard: () -> Void
    let stop: () -> Void
    let togglePause: () -> Void
    let markMoment: () -> Void
    let addTask: () -> Void
    let snapWhiteboard: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.adaptiveCanExpandWindow) private var canExpandWindow
    @Environment(\.adaptiveHingeState) private var hingeState
    @State private var confirmsDiscard = false
    @State private var actionFeedback: String?

    var body: some View {
        // Large windows (iPad, a propped Duo inner screen) switch to the
        // tabletop layout; the recorder state is the same either way.
        VStack(spacing: 0) {
            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(Geist.body())
                    .foregroundStyle(Color(captureHex: 0xF4F4F1))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Geist.recording.opacity(0.22))
                    .accessibilityIdentifier("capture_live_recording_error")
            }
            recordingLayout
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(captureHex: 0x0B0B0B).ignoresSafeArea())
        .foregroundStyle(Color(captureHex: 0xF4F4F1))
        .environment(\.colorScheme, .dark)
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
        .accessibilityIdentifier("capture_live_recording_screen")
    }

    private var recordingLayout: some View {
        GeometryReader { proxy in
            Group {
                if AdaptiveLayout.usesTabletopRecording(
                    size: proxy.size,
                    horizontalSizeClass: horizontalSizeClass,
                    hinge: hingeState
                ) {
                    CaptureTabletopRecordingLayout(
                        screen: self,
                        feedback: actionFeedback,
                        confirmDiscard: { confirmsDiscard = true },
                        flash: flash
                    )
                } else if proxy.size.height < 440 || AdaptiveLayout.isCoverScreen(
                    horizontalSizeClass: horizontalSizeClass,
                    hinge: hingeState
                ) {
                    coverLayout
                } else {
                    standardLayout
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// The phone (and Duo cover) recording layout.
    private var standardLayout: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 8)
            timerRow
                .padding(.horizontal, 24)
                .padding(.top, 28)
            transcript
                .padding(.horizontal, 24)
                .padding(.top, 28)
            CaptureLiveRecordingWaveform(levels: levels, isPaused: isPaused)
                .frame(height: 72)
                .padding(.horizontal, 24)
            if canExpandWindow {
                AdaptiveExpandHint(kind: .recording)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
            }
            footer
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The foldable cover-screen recording layout (Signal "Duo cover ·
    /// recording"): route pill and a compact timer in the header, the live
    /// transcript, a shorter waveform, the open hint and the three controls.
    private var coverLayout: some View {
        VStack(spacing: 0) {
            HStack {
                routePill
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(isPaused ? Color(captureHex: 0x9A9A95) : Geist.recording)
                        .frame(width: 9, height: 9)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    Text(verbatim: duration)
                        .font(.custom("GeistMono-Medium", size: 22, relativeTo: .title2))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(isPaused
                    ? String(localized: "Paused, \(duration)")
                    : String(localized: "Recording, \(duration)")))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            coverTranscript
                .padding(.horizontal, 24)
                .padding(.top, 22)
            CaptureLiveRecordingWaveform(levels: levels, isPaused: isPaused)
                .frame(height: 52)
                .padding(.horizontal, 24)
            if canExpandWindow {
                AdaptiveExpandHint(kind: .recording)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
            }
            coverControls
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var coverTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    let items = paragraphs
                    if items.isEmpty && volatileText.isEmpty && errorMessage == nil {
                        Text(isPaused ? String(localized: "Paused — resume to keep recording this note.") : String(localized: "Start talking…"))
                            .font(.custom("Geist-Medium", size: 19, relativeTo: .title3))
                            .foregroundStyle(Color(captureHex: 0x8A8A85))
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, paragraph in
                        let isLast = index == items.count - 1
                        coverParagraph(paragraph, volatile: isLast ? volatileText : "", isCurrent: isLast)
                    }
                    if items.isEmpty, !volatileText.isEmpty {
                        coverParagraph(Paragraph(id: -1, speaker: nil, text: ""), volatile: volatileText, isCurrent: true)
                    }
                    Color.clear.frame(height: 1).id("tail")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: lines.count) { _, _ in scrollToTail(proxy) }
            .onChange(of: volatileText) { _, _ in scrollToTail(proxy) }
        }
        .frame(maxHeight: .infinity)
        .accessibilityLabel(Text("Live transcript"))
        // The cover board has no action chips; keep them for VoiceOver.
        .accessibilityAction(named: Text("Mark moment")) {
            markMoment()
            flash(String(localized: "Moment marked at \(duration)"))
        }
        .accessibilityAction(named: Text("Add task")) {
            addTask()
            flash(String(localized: "Task added to draft"))
        }
    }

    private func coverParagraph(_ paragraph: Paragraph, volatile: String, isCurrent: Bool) -> some View {
        CaptureLiveCaretText(
            text: Text(verbatim: paragraph.text)
                + Text(verbatim: volatile.isEmpty ? "" : (paragraph.text.isEmpty ? volatile : " " + volatile))
                    .foregroundColor(Color(captureHex: 0x8A8A85)),
            showsCaret: isCurrent && !isPaused
        )
            .font(.custom("Geist-Medium", size: 19, relativeTo: .title3))
            .foregroundStyle(isCurrent ? Color(captureHex: 0xF4F4F1) : Color(captureHex: 0x8A8A85))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var coverControls: some View {
        HStack {
            Button {
                confirmsDiscard = true
            } label: {
                Image(systemName: "xmark")
                    .accessibilityLabel(Text("Discard recording"))
            }
            .buttonStyle(SignalCircleButtonStyle(diameter: 52, filled: Color(captureHex: 0x1C1C1C)))
            .accessibilityIdentifier("capture_recording_discard")

            Spacer(minLength: 16)

            Button(action: stop) {
                CaptureStopRingLabel(diameter: 80)
                    .accessibilityLabel(Text(isDraftMode ? "Stop and add to draft" : "Stop and send"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("capture_recording_stop_send")

            Spacer(minLength: 16)

            Button(action: togglePause) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .accessibilityLabel(Text(isPaused ? "Resume recording" : "Pause recording"))
            }
            .buttonStyle(SignalCircleButtonStyle(
                diameter: 52,
                filled: isPaused ? Geist.accent : Color(captureHex: 0x1C1C1C)
            ))
            .accessibilityIdentifier("capture_recording_pause_toggle")
        }
        .overlay(alignment: .top) {
            if let actionFeedback {
                Text(verbatim: actionFeedback)
                    .font(Geist.caption(.caption))
                    .foregroundStyle(Color(captureHex: 0x0B0B0B))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color(captureHex: 0xF4F4F1), in: Capsule())
                    .offset(y: -40)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Header

    private var routePill: some View {
        HStack(spacing: 8) {
            SignalRouteTile(letter: routeName, size: 22, circular: true, tone: routeTone)
            Text(verbatim: routeName)
                .font(.custom("Geist-SemiBold", size: 14, relativeTo: .subheadline))
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: 32)
        .background(Color(captureHex: 0x1C1C1C), in: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Recording to \(routeName)"))
    }

    private var header: some View {
        HStack {
            routePill

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(verbatim: onDeviceLabel)
                    .font(Geist.mono(size: 11.5, relativeTo: .caption))
            }
            .foregroundStyle(Color(captureHex: 0x9A9A95))
            .accessibilityElement(children: .combine)
        }
    }

    private var onDeviceLabel: String {
        if showsSpeakerLabels, speakerCount > 1 {
            return String(localized: "On device · \(speakerCount) speakers")
        }
        return String(localized: "On device")
    }

    private var timerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle()
                .fill(isPaused ? Color(captureHex: 0x9A9A95) : Geist.recording)
                .frame(width: 10, height: 10)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
            Text(verbatim: duration)
                .font(.custom("GeistMono-Medium", size: 44, relativeTo: .largeTitle))
                .monospacedDigit()
                .tracking(-0.9)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: isPaused ? String(localized: "Paused") : engineLabel)
                .font(Geist.caption(.footnote))
                .foregroundStyle(Color(captureHex: 0x9A9A95))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Transcript

    private struct Paragraph: Identifiable {
        let id: Int
        let speaker: String?
        var text: String
    }

    private var paragraphs: [Paragraph] {
        var result: [Paragraph] = []
        for line in lines {
            let label = showsSpeakerLabels ? line.speakerLabel : nil
            if var last = result.last, last.speaker == label {
                last.text += " " + line.text
                result[result.count - 1] = last
            } else {
                result.append(Paragraph(id: line.id, speaker: label, text: line.text))
            }
        }
        return result
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    let items = paragraphs
                    if items.isEmpty && volatileText.isEmpty && errorMessage == nil {
                        Text(isPaused ? String(localized: "Paused — resume to keep recording this note.") : String(localized: "Start talking…"))
                            .font(.custom("Geist-Medium", size: 21, relativeTo: .title3))
                            .foregroundStyle(Color(captureHex: 0x8A8A85))
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, paragraph in
                        let isLast = index == items.count - 1
                        paragraphRow(
                            paragraph,
                            volatile: isLast ? volatileText : "",
                            showsCaret: isLast && !isPaused
                        )
                    }
                    if items.isEmpty, !volatileText.isEmpty {
                        paragraphRow(
                            Paragraph(id: -1, speaker: nil, text: ""),
                            volatile: volatileText,
                            showsCaret: !isPaused
                        )
                    }
                    Color.clear.frame(height: 1).id("tail")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: lines.count) { _, _ in scrollToTail(proxy) }
            .onChange(of: volatileText) { _, _ in scrollToTail(proxy) }
        }
        .frame(maxHeight: .infinity)
        .accessibilityLabel(Text("Live transcript"))
    }

    private func scrollToTail(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            proxy.scrollTo("tail", anchor: .bottom)
        }
    }

    private func paragraphRow(_ paragraph: Paragraph, volatile: String, showsCaret: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if showsSpeakerLabels {
                Text(verbatim: paragraph.speaker ?? "")
                    .font(Geist.mono(size: 11, relativeTo: .caption2))
                    .foregroundStyle(Color(captureHex: 0x9A9A95))
                    .frame(width: 22, alignment: .leading)
                    .padding(.top, 5)
            }
            CaptureLiveCaretText(
                text: Text(verbatim: paragraph.text)
                    + Text(verbatim: volatile.isEmpty ? "" : (paragraph.text.isEmpty ? volatile : " " + volatile))
                        .foregroundColor(Color(captureHex: 0x8A8A85)),
                showsCaret: showsCaret
            )
                .font(.custom("Geist-Medium", size: 21, relativeTo: .title3))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 18) {
            actionChips
            if let liveNoteLine {
                LiveNoteRecordingLineView(text: liveNoteLine, isLive: liveNoteLineIsLive)
            } else {
                CaptureRecordingModeSegment(isDraft: $isDraftMode, isLocked: isModeLocked)
            }
            HStack {
                Button {
                    confirmsDiscard = true
                } label: {
                    Image(systemName: "xmark")
                        .accessibilityLabel(Text("Discard recording"))
                }
                .buttonStyle(SignalCircleButtonStyle(diameter: 56, filled: Color(captureHex: 0x1C1C1C)))
                .accessibilityIdentifier("capture_recording_discard")

                Spacer(minLength: 16)

                Button(action: stop) {
                    CaptureStopRingLabel()
                        .accessibilityLabel(Text(isDraftMode ? "Stop and add to draft" : "Stop and send"))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("capture_recording_stop_send")

                Spacer(minLength: 16)

                Button(action: togglePause) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .accessibilityLabel(Text(isPaused ? "Resume recording" : "Pause recording"))
                }
                .buttonStyle(SignalCircleButtonStyle(
                    diameter: 56,
                    filled: isPaused ? Geist.accent : Color(captureHex: 0x1C1C1C)
                ))
                .accessibilityIdentifier("capture_recording_pause_toggle")
            }
            .padding(.horizontal, 12)
        }
        .overlay(alignment: .top) {
            if let actionFeedback {
                Text(verbatim: actionFeedback)
                    .font(Geist.caption(.caption))
                    .foregroundStyle(Color(captureHex: 0x0B0B0B))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color(captureHex: 0xF4F4F1), in: Capsule())
                    .offset(y: -40)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    private var actionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(String(localized: "Mark moment"), systemImage: "bookmark") {
                    markMoment()
                    flash(String(localized: "Moment marked at \(duration)"))
                }
                .accessibilityIdentifier("capture_recording_mark_moment")
                chip(String(localized: "Add task"), systemImage: "checklist") {
                    addTask()
                    flash(String(localized: "Task added to draft"))
                }
                .accessibilityIdentifier("capture_recording_add_task")
                chip(String(localized: "Snap whiteboard"), systemImage: "camera") {
                    snapWhiteboard()
                }
                .disabled(!canSnapWhiteboard)
                .opacity(canSnapWhiteboard ? 1 : 0.4)
                .accessibilityIdentifier("capture_recording_snap_whiteboard")
            }
        }
    }

    private func chip(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleOnly)
                .font(.custom("Geist-Medium", size: 14, relativeTo: .subheadline))
                .foregroundStyle(Color(captureHex: 0xF4F4F1))
                .lineLimit(1)
                // 12pt keeps all three chips inside a 402pt-wide iPhone.
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Color(captureHex: 0x1C1C1C), in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).stroke(Color(captureHex: 0x2A2A28), lineWidth: 1))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
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

/// Live transcript text followed by the blinking red recording caret from
/// the Signal "Live recording" board. Reduce Motion keeps the caret steady.
struct CaptureLiveCaretText: View {
    let text: Text
    let showsCaret: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let blinkInterval: TimeInterval = 0.53

    var body: some View {
        if showsCaret {
            TimelineView(.periodic(from: .now, by: Self.blinkInterval)) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate / Self.blinkInterval)
                let isOn = reduceMotion || tick.isMultiple(of: 2)
                // U+258F (one-eighth block): a thin 2pt bar like the board's
                // caret; the wider U+258D read as a solid block.
                (text + Text(verbatim: "\u{200A}\u{258F}")
                    .foregroundColor(isOn ? Geist.recording : .clear))
                    .accessibilityLabel(text)
            }
        } else {
            text
        }
    }
}

/// 48-bar live waveform: recent levels in recording red, history in grey.
struct CaptureLiveRecordingWaveform: View {
    let levels: [Float]
    var isPaused = false

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color(for: index))
                        .frame(height: max(8, geometry.size.height * 0.85 * CGFloat(min(1, max(0, level)))))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.08), value: levels)
        .accessibilityHidden(true)
    }

    private func color(for index: Int) -> Color {
        guard !isPaused else { return Color(captureHex: 0x3A3A38) }
        return index >= levels.count - 7 ? Geist.recording : Color(captureHex: 0x3A3A38)
    }
}

extension Color {
    /// Literal sRGB color for fixed dark recording surfaces.
    init(captureHex hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
