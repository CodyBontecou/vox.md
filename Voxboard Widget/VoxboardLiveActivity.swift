import ActivityKit
import AppIntents
import SwiftUI
import VoxboardShared
import WidgetKit

@available(iOS 17.0, *)
struct VoxboardLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoxboardActivityAttributes.self) { context in
            LockScreenBanner(state: context.state)
                .padding(16)
                .activityBackgroundTint(SignalActivity.ground)
                .activitySystemActionForegroundColor(SignalActivity.text)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        if context.state.routeMonogram != nil {
                            RouteTile(state: context.state, size: 22)
                        } else {
                            Image(systemName: context.state.activitySymbolName(expanded: true))
                                .foregroundStyle(context.state.activityTint)
                                .font(.headline)
                        }
                        Text(context.state.routeName ?? context.state.activityTitle)
                            .font(SignalWidgetFont.sans(15, .semibold))
                            .foregroundStyle(SignalActivity.text)
                            .liveActivitySingleLine(minimumScaleFactor: 0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isSegmentActive || context.state.transcriptionPercentLabel != nil {
                        ElapsedReadout(state: context.state, size: 17)
                    } else {
                        Text(context.state.isTranscribing
                             ? String(localized: "Working")
                             : String(localized: "Ready"))
                            .font(SignalWidgetFont.sans(17, .semibold))
                            .foregroundStyle(SignalActivity.muted)
                            .liveActivitySingleLine(minimumScaleFactor: 0.72)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if let path = context.state.destinationPath,
                           context.state.isSegmentActive || context.state.isTranscribing {
                            Text("→ \(path)")
                                .font(SignalWidgetFont.mono(11))
                                .foregroundStyle(SignalActivity.muted)
                                .liveActivitySingleLine(minimumScaleFactor: 0.72)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let progress = context.state.transcriptionProgress,
                           let percent = context.state.transcriptionPercentLabel,
                           context.state.isTranscribing {
                            ProgressView(value: progress)
                                .tint(SignalActivity.text)
                                .accessibilityLabel("Transcription progress")
                                .accessibilityValue("\(percent) complete")
                        }
                        if context.state.isSegmentActive {
                            HStack(spacing: 12) {
                                LevelBars(state: context.state, barCount: 32, height: 26, liveTail: 6)
                                if context.state.canPause == true {
                                    PauseButton(state: context.state)
                                }
                                RecordButton(state: context.state, compact: true)
                            }
                        } else {
                            RecordButton(state: context.state, compact: false)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.activitySymbolName(expanded: false))
                    .foregroundStyle(context.state.activityTint)
            } compactTrailing: {
                if let paused = context.state.pausedElapsed, context.state.isSegmentActive {
                    Text(ElapsedReadout.format(paused))
                        .monospacedDigit()
                        .font(SignalWidgetFont.mono(17, medium: true))
                        .foregroundStyle(SignalActivity.muted)
                        .frame(maxWidth: 44)
                        .liveActivitySingleLine(minimumScaleFactor: 0.7)
                } else if let started = context.state.segmentStartedAt, context.state.isSegmentActive {
                    Text(Date(timeIntervalSince1970: started), style: .timer)
                        .monospacedDigit()
                        .font(SignalWidgetFont.mono(17, medium: true))
                        .foregroundStyle(SignalActivity.red)
                        .frame(maxWidth: 44)
                        .liveActivitySingleLine(minimumScaleFactor: 0.7)
                } else if let percent = context.state.transcriptionPercentLabel {
                    Text(percent)
                        .monospacedDigit()
                        .font(SignalWidgetFont.sans(11, .semibold))
                        .foregroundStyle(SignalActivity.text)
                        .liveActivitySingleLine(minimumScaleFactor: 0.7)
                } else if context.state.isTranscribing {
                    Text("…")
                        .font(SignalWidgetFont.sans(12, .semibold))
                        .foregroundStyle(SignalActivity.muted)
                        .liveActivitySingleLine()
                } else {
                    Text("Ready")
                        .font(SignalWidgetFont.sans(11))
                        .foregroundStyle(SignalActivity.muted)
                        .liveActivitySingleLine(minimumScaleFactor: 0.7)
                }
            } minimal: {
                Image(systemName: context.state.activitySymbolName(expanded: false))
                    .foregroundStyle(context.state.activityTint)
            }
        }
    }
}

@available(iOS 17.0, *)
private struct LockScreenBanner: View {
    let state: VoxboardLiveActivityState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RouteTile(state: state)

                VStack(alignment: .leading, spacing: 1) {
                    Text(state.routeName ?? "Vox.md")
                        .font(SignalWidgetFont.sans(15, .semibold))
                        .foregroundStyle(SignalActivity.text)
                        .liveActivitySingleLine()
                    subtitle
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                ElapsedReadout(state: state, size: 22)
                    .frame(maxWidth: 96, alignment: .trailing)
            }

            HStack(spacing: 12) {
                if let progress = state.transcriptionProgress,
                   state.transcriptionPercentLabel != nil,
                   state.isTranscribing {
                    ProgressView(value: progress)
                        .tint(SignalActivity.text)
                } else if state.isSegmentActive {
                    LevelBars(state: state)
                } else {
                    Capsule()
                        .fill(SignalActivity.hairline)
                        .frame(height: 2)
                        .accessibilityHidden(true)
                }
                if state.isSegmentActive, state.canPause == true {
                    PauseButton(state: state)
                }
                RecordButton(state: state, compact: true)
            }
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        Group {
            if let path = state.destinationPath, state.isSegmentActive || state.isTranscribing {
                if state.isPaused {
                    Text("Paused · → \(path)")
                } else if let percent = state.transcriptionPercentLabel {
                    Text("\(percent) · → \(path)")
                } else if state.isTranscribing {
                    Text("Sending → \(path)")
                } else {
                    Text("→ \(path)")
                }
            } else if state.isPaused {
                Text("Paused")
            } else if state.isSegmentActive {
                Text("Recording")
            } else if let percent = state.transcriptionPercentLabel {
                Text("Processing audio · \(percent)")
            } else {
                Text(state.isTranscribing
                     ? String(localized: "Processing audio")
                     : String(localized: "Tap to record"))
            }
        }
        .font(SignalWidgetFont.mono(11))
        .foregroundStyle(SignalActivity.muted)
        .liveActivitySingleLine(minimumScaleFactor: 0.72)
        .truncationMode(.middle)
    }
}

/// Route-style badge: indigo tile with the route's initial; mic glyph when
/// the recording has no route (keyboard dictation, monitor idle).
@available(iOS 17.0, *)
private struct RouteTile: View {
    let state: VoxboardLiveActivityState
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle()
                .fill(state.routeMonogram == nil && state.isSegmentActive ? SignalActivity.red : SignalActivity.accent)
            if let monogram = state.routeMonogram {
                Text(monogram)
                    .font(SignalWidgetFont.sans(size * 0.46, .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
            } else {
                Image(systemName: state.activitySymbolName(expanded: false))
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Running timer while recording; frozen recorded time while paused.
@available(iOS 17.0, *)
private struct ElapsedReadout: View {
    let state: VoxboardLiveActivityState
    let size: CGFloat

    var body: some View {
        if state.isSegmentActive {
            Group {
                if let paused = state.pausedElapsed {
                    Text(Self.format(paused))
                        .foregroundStyle(SignalActivity.muted)
                } else if let started = state.segmentStartedAt {
                    Text(Date(timeIntervalSince1970: started), style: .timer)
                        .foregroundStyle(SignalActivity.red)
                }
            }
            .font(SignalWidgetFont.mono(size, medium: true))
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .liveActivitySingleLine(minimumScaleFactor: 0.7)
        } else if let percent = state.transcriptionPercentLabel {
            Text(percent)
                .font(SignalWidgetFont.mono(size * 0.8, medium: true))
                .monospacedDigit()
                .foregroundStyle(SignalActivity.text)
                .liveActivitySingleLine(minimumScaleFactor: 0.7)
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

/// Recent microphone level history. The newest bars are tinted red, matching
/// the Signal recording waveform; paused audio renders entirely muted.
@available(iOS 17.0, *)
private struct LevelBars: View {
    let state: VoxboardLiveActivityState
    var barCount: Int = VoxboardLiveActivityState.maximumAudioLevelCount
    var height: CGFloat = 30
    var liveTail: Int = 7

    var body: some View {
        let levels = paddedLevels
        HStack(alignment: .center, spacing: 2) {
            ForEach(levels.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(color(at: index, count: levels.count))
                    .frame(height: barHeight(levels[index]))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var paddedLevels: [UInt8] {
        let history = Array((state.audioLevels ?? []).suffix(barCount))
        return Array(repeating: 0, count: max(0, barCount - history.count)) + history
    }

    private func barHeight(_ level: UInt8) -> CGFloat {
        let minimum: CGFloat = 4
        return minimum + (height - minimum) * CGFloat(min(level, 100)) / 100
    }

    private func color(at index: Int, count: Int) -> Color {
        guard !state.isPaused, index >= count - liveTail else { return SignalActivity.bar }
        return SignalActivity.red
    }
}

@available(iOS 17.0, *)
private struct PauseButton: View {
    let state: VoxboardLiveActivityState
    var compact: Bool = true

    var body: some View {
        Button(intent: TogglePauseRecordingLiveActivityIntent(requestId: state.segmentRequestId)) {
            ZStack {
                Circle().fill(SignalActivity.control)
                Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(SignalActivity.text)
            }
            .frame(width: 44, height: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.isPaused ? "Resume" : "Pause")
        }
        .buttonStyle(.plain)
    }
}

@available(iOS 17.0, *)
private struct RecordButton: View {
    let state: VoxboardLiveActivityState
    let compact: Bool

    var body: some View {
        if state.isSegmentActive {
            Button(intent: StopRecordingLiveActivityIntent(requestId: state.segmentRequestId)) {
                if compact {
                    // Signal stop: red 44pt circle with a white rounded square.
                    ZStack {
                        Circle().fill(SignalActivity.red)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(.white)
                            .frame(width: 14, height: 14)
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Stop and send")
                } else {
                    Label("Stop and send", systemImage: "stop.fill")
                        .labelStyle(.titleAndIcon)
                        .font(SignalWidgetFont.sans(17, .semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(SignalActivity.red, in: Capsule())
                        .foregroundStyle(.white)
                        .liveActivitySingleLine(minimumScaleFactor: 0.8)
                }
            }
            .buttonStyle(.plain)
        } else if state.isTranscribing {
            Group {
                if let percent = state.transcriptionPercentLabel {
                    Label(percent, systemImage: "hourglass")
                } else {
                    Label("Processing", systemImage: "hourglass")
                }
            }
                .labelStyle(.titleAndIcon)
                .font(compact ? SignalWidgetFont.sans(15, .semibold).monospacedDigit() : SignalWidgetFont.sans(17, .semibold).monospacedDigit())
                .padding(.horizontal, compact ? 14 : 20)
                .padding(.vertical, compact ? 8 : 12)
                .background(SignalActivity.control, in: Capsule())
                .foregroundStyle(SignalActivity.text)
                .liveActivitySingleLine(minimumScaleFactor: compact ? 0.72 : 0.8)
        } else {
            Button(intent: StartRecordingLiveActivityIntent()) {
                Label {
                    Text("Record")
                } icon: {
                    Circle()
                        .fill(SignalActivity.red)
                        .frame(width: 10, height: 10)
                }
                    .labelStyle(.titleAndIcon)
                    .font(compact ? SignalWidgetFont.sans(15, .semibold) : SignalWidgetFont.sans(17, .semibold))
                    .padding(.horizontal, compact ? 14 : 20)
                    .padding(.vertical, compact ? 8 : 12)
                    .background(SignalActivity.text, in: Capsule())
                    .foregroundStyle(SignalActivity.ground)
                    .liveActivitySingleLine(minimumScaleFactor: compact ? 0.72 : 0.8)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Signal palette for the Live Activity (the extension does not compile
/// the main app's GeistTheme tokens).
private enum SignalActivity {
    static let ground = Color(red: 11 / 255, green: 11 / 255, blue: 11 / 255)      // #0B0B0B
    static let control = Color(red: 38 / 255, green: 38 / 255, blue: 38 / 255)     // #262626
    static let hairline = Color(red: 42 / 255, green: 42 / 255, blue: 40 / 255)    // #2A2A28
    static let text = Color(red: 244 / 255, green: 244 / 255, blue: 241 / 255)     // #F4F4F1
    static let muted = Color(red: 154 / 255, green: 154 / 255, blue: 149 / 255)    // #9A9A95
    static let accent = Color(red: 47 / 255, green: 59 / 255, blue: 232 / 255)     // #2F3BE8
    static let accentTint = Color(red: 138 / 255, green: 143 / 255, blue: 255 / 255) // #8A8FFF
    static let red = Color(red: 240 / 255, green: 71 / 255, blue: 74 / 255)        // #F0474A
    static let bar = Color(red: 74 / 255, green: 74 / 255, blue: 71 / 255)         // #4A4A47
}

@available(iOS 17.0, *)
private extension View {
    func liveActivitySingleLine(minimumScaleFactor: CGFloat = 0.75) -> some View {
        lineLimit(1)
            .minimumScaleFactor(minimumScaleFactor)
            .allowsTightening(true)
    }
}

@available(iOS 17.0, *)
private extension VoxboardLiveActivityState {
    var transcriptionPercentLabel: String? {
        guard isTranscribing,
              let transcriptionProgress,
              transcriptionProgress.isFinite else { return nil }
        let wholePercent = Int(
            (min(1, max(0, transcriptionProgress)) * 100).rounded(.down)
        )
        return (Double(wholePercent) / 100).formatted(
            .percent.precision(.fractionLength(0))
        )
    }

    var activityTitle: String {
        if isSegmentActive { return String(localized: "Recording") }
        if isTranscribing { return String(localized: "Processing") }
        return "Vox.md"
    }

    var activityTint: Color {
        if isSegmentActive { return SignalActivity.red }
        if isTranscribing { return SignalActivity.text }
        return SignalActivity.accentTint
    }

    func activitySymbolName(expanded: Bool) -> String {
        if isPaused { return expanded ? "pause.circle.fill" : "pause.fill" }
        if isSegmentActive { return expanded ? "waveform.circle.fill" : "waveform" }
        if isTranscribing { return expanded ? "hourglass.circle" : "hourglass" }
        return expanded ? "mic.circle" : "mic.fill"
    }
}
