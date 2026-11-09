import SwiftUI
import VoxboardShared

/// DuoTabletop: the live recording surface for a propped, wide screen. The top
/// half reads like a teleprompter (live transcript with speaker labels); the
/// bottom half holds the big timer and every control. All state and commands
/// come from `CaptureLiveRecordingScreen`, which gets them from the shared
/// recorder, so switching layouts never interrupts a recording.
struct CaptureTabletopRecordingLayout: View {
    let screen: CaptureLiveRecordingScreen
    let feedback: String?
    let confirmDiscard: () -> Void
    let flash: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let ink = Color(captureHex: 0xF4F4F1)
    private static let dim = Color(captureHex: 0x8A8A85)
    private static let quiet = Color(captureHex: 0x9A9A95)
    private static let chip = Color(captureHex: 0x1C1C1C)

    var body: some View {
        VStack(spacing: 0) {
            transcriptHalf
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            hinge
            controlsHalf
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(captureHex: 0x121212).ignoresSafeArea(edges: [.bottom, .horizontal]))
        }
        .accessibilityIdentifier("capture_tabletop_recording")
    }

    // MARK: Top half

    private var transcriptHalf: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                routeChip
                Spacer(minLength: 8)
                Text(verbatim: onDeviceLabel)
                    .font(Geist.mono(size: 11.5, relativeTo: .caption))
                    .foregroundStyle(Self.quiet)
            }
            transcript
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    private var routeChip: some View {
        HStack(spacing: 8) {
            SignalRouteTile(letter: screen.routeName, size: 22, circular: true, tone: screen.routeTone)
            Text(verbatim: screen.routeName)
                .font(.custom("Geist-SemiBold", size: 14, relativeTo: .subheadline))
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: 32)
        .background(Self.chip, in: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Recording to \(screen.routeName)"))
    }

    private var onDeviceLabel: String {
        if screen.showsSpeakerLabels, screen.speakerCount > 1 {
            return String(localized: "On device · \(screen.speakerCount) speakers")
        }
        return String(localized: "On device")
    }

    private struct Paragraph: Identifiable {
        let id: Int
        let speaker: String?
        var text: String
    }

    private var paragraphs: [Paragraph] {
        var result: [Paragraph] = []
        for line in screen.lines {
            let label = screen.showsSpeakerLabels ? line.speakerLabel : nil
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
                VStack(alignment: .leading, spacing: 14) {
                    Spacer(minLength: 0)
                    let items = paragraphs
                    if items.isEmpty && screen.volatileText.isEmpty && screen.errorMessage == nil {
                        Text(screen.isPaused
                            ? String(localized: "Paused — resume to keep recording this note.")
                            : String(localized: "Start talking…"))
                            .font(.custom("Geist-Medium", size: 24, relativeTo: .title2))
                            .foregroundStyle(Self.dim)
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, paragraph in
                        let isLast = index == items.count - 1
                        row(paragraph, volatile: isLast ? screen.volatileText : "", isCurrent: isLast)
                    }
                    if items.isEmpty, !screen.volatileText.isEmpty {
                        row(Paragraph(id: -1, speaker: nil, text: ""), volatile: screen.volatileText, isCurrent: true)
                    }
                    Color.clear.frame(height: 1).id("tail")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: screen.lines.count) { _, _ in scrollToTail(proxy) }
            .onChange(of: screen.volatileText) { _, _ in scrollToTail(proxy) }
        }
        .accessibilityLabel(Text("Live transcript"))
    }

    private func scrollToTail(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            proxy.scrollTo("tail", anchor: .bottom)
        }
    }

    private func row(_ paragraph: Paragraph, volatile: String, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if screen.showsSpeakerLabels {
                Text(verbatim: paragraph.speaker ?? "")
                    .font(Geist.mono(size: 11, relativeTo: .caption2))
                    .foregroundStyle(Self.quiet)
                    .frame(width: 22, alignment: .leading)
                    .padding(.top, 6)
            }
            CaptureLiveCaretText(
                text: Text(verbatim: paragraph.text)
                    + Text(verbatim: volatile.isEmpty ? "" : (paragraph.text.isEmpty ? volatile : " " + volatile))
                        .foregroundColor(Self.dim),
                showsCaret: isCurrent && !screen.isPaused
            )
                .font(.custom("Geist-Medium", size: isCurrent ? 24 : 20, relativeTo: .title2))
                .foregroundStyle(isCurrent ? Self.ink : Self.dim)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hinge: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0.08), location: 0.2),
                .init(color: .white.opacity(0.08), location: 0.8),
                .init(color: .white.opacity(0), location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    // MARK: Bottom half

    private var controlsHalf: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Circle()
                    .fill(screen.isPaused ? Self.quiet : Geist.recording)
                    .frame(width: 10, height: 10)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                Text(verbatim: screen.duration)
                    .font(.custom("GeistMono-Medium", size: 40, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .tracking(-0.8)
                    .lineLimit(1)
                Text(screen.isPaused ? String(localized: "Paused") : String(localized: "Hands-free · keeps going while propped"))
                    .font(Geist.caption(.footnote))
                    .foregroundStyle(Self.quiet)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            CaptureLiveRecordingWaveform(levels: screen.levels, isPaused: screen.isPaused)
                .frame(height: 56)

            HStack(spacing: 8) {
                chip(String(localized: "Mark moment")) {
                    screen.markMoment()
                    flash(String(localized: "Moment marked at \(screen.duration)"))
                }
                .accessibilityIdentifier("capture_recording_mark_moment")
                chip(String(localized: "Add task")) {
                    screen.addTask()
                    flash(String(localized: "Task added to draft"))
                }
                .accessibilityIdentifier("capture_recording_add_task")
                chip(String(localized: "Snap whiteboard")) {
                    screen.snapWhiteboard()
                }
                .disabled(!screen.canSnapWhiteboard)
                .opacity(screen.canSnapWhiteboard ? 1 : 0.4)
                .accessibilityIdentifier("capture_recording_snap_whiteboard")
                Spacer(minLength: 0)
                if let feedback {
                    Text(verbatim: feedback)
                        .font(Geist.caption(.caption))
                        .foregroundStyle(Color(captureHex: 0x0B0B0B))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Self.ink, in: Capsule())
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 40) {
                Button(action: confirmDiscard) {
                    Image(systemName: "xmark")
                        .accessibilityLabel(Text("Discard recording"))
                }
                .buttonStyle(SignalCircleButtonStyle(diameter: 56, filled: Self.chip))
                .accessibilityIdentifier("capture_recording_discard")

                Button(action: screen.stop) {
                    CaptureStopRingLabel(diameter: 88)
                        .accessibilityLabel(Text(screen.isDraftMode ? "Stop and add to draft" : "Stop and send"))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier("capture_recording_stop_send")

                Button(action: screen.togglePause) {
                    Image(systemName: screen.isPaused ? "play.fill" : "pause.fill")
                        .accessibilityLabel(Text(screen.isPaused ? "Resume recording" : "Pause recording"))
                }
                .buttonStyle(SignalCircleButtonStyle(
                    diameter: 56,
                    filled: screen.isPaused ? Geist.accent : Self.chip
                ))
                .accessibilityIdentifier("capture_recording_pause_toggle")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 32)
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.custom("Geist-Medium", size: 14, relativeTo: .subheadline))
                .foregroundStyle(Self.ink)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Self.chip, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).stroke(Color(captureHex: 0x2A2A28), lineWidth: 1))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
