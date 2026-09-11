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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.activitySymbolName(expanded: true))
                            .foregroundStyle(context.state.activityTint)
                            .font(.headline)
                        Text(context.state.activityTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .liveActivitySingleLine(minimumScaleFactor: 0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let started = context.state.segmentStartedAt, context.state.isSegmentActive {
                        Text(Date(timeIntervalSince1970: started), style: .timer)
                            .monospacedDigit()
                            .font(.headline)
                            .foregroundStyle(.white)
                            .liveActivitySingleLine(minimumScaleFactor: 0.78)
                    } else if let percent = context.state.transcriptionPercentLabel {
                        Text(percent)
                            .monospacedDigit()
                            .font(.headline)
                            .foregroundStyle(.white)
                            .liveActivitySingleLine(minimumScaleFactor: 0.78)
                    } else {
                        Text(context.state.isTranscribing
                             ? String(localized: "Working")
                             : String(localized: "Ready"))
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.7))
                            .liveActivitySingleLine(minimumScaleFactor: 0.72)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if let progress = context.state.transcriptionProgress,
                           let percent = context.state.transcriptionPercentLabel,
                           context.state.isTranscribing {
                            ProgressView(value: progress)
                                .tint(.white)
                                .accessibilityLabel("Transcription progress")
                                .accessibilityValue("\(percent) complete")
                        }
                        RecordButton(state: context.state, compact: false)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.activitySymbolName(expanded: false))
                    .foregroundStyle(context.state.activityTint)
            } compactTrailing: {
                if let started = context.state.segmentStartedAt, context.state.isSegmentActive {
                    Text(Date(timeIntervalSince1970: started), style: .timer)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                        .liveActivitySingleLine(minimumScaleFactor: 0.7)
                } else if let percent = context.state.transcriptionPercentLabel {
                    Text(percent)
                        .monospacedDigit()
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .liveActivitySingleLine(minimumScaleFactor: 0.7)
                } else if context.state.isTranscribing {
                    Text("…")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .liveActivitySingleLine()
                } else {
                    Text("Ready")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
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
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(state.isSegmentActive ? Color.red.opacity(0.2) : Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: state.activitySymbolName(expanded: false))
                    .foregroundStyle(state.activityTint)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Vox.md")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .liveActivitySingleLine()
                if let started = state.segmentStartedAt, state.isSegmentActive {
                    HStack(spacing: 4) {
                        Text("Recording")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .liveActivitySingleLine(minimumScaleFactor: 0.72)
                        Text(Date(timeIntervalSince1970: started), style: .timer)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white)
                            .liveActivitySingleLine(minimumScaleFactor: 0.78)
                    }
                    .accessibilityElement(children: .combine)
                } else if let percent = state.transcriptionPercentLabel,
                          let progress = state.transcriptionProgress {
                    Text("Processing audio · \(percent)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .liveActivitySingleLine(minimumScaleFactor: 0.72)
                    ProgressView(value: progress)
                        .tint(.white)
                } else {
                    Text(state.isTranscribing
                         ? String(localized: "Processing audio")
                         : String(localized: "Tap to record"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .liveActivitySingleLine(minimumScaleFactor: 0.72)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            RecordButton(state: state, compact: true)
        }
    }
}

@available(iOS 17.0, *)
private struct RecordButton: View {
    let state: VoxboardLiveActivityState
    let compact: Bool

    var body: some View {
        if state.isSegmentActive {
            Button(intent: StopRecordingLiveActivityIntent(requestId: state.segmentRequestId)) {
                Label("Stop", systemImage: "stop.fill")
                    .labelStyle(.titleAndIcon)
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                    .padding(.horizontal, compact ? 14 : 20)
                    .padding(.vertical, compact ? 8 : 12)
                    .background(Color.red, in: Capsule())
                    .foregroundStyle(.white)
                    .liveActivitySingleLine(minimumScaleFactor: compact ? 0.72 : 0.8)
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
                .font(compact ? .subheadline.weight(.semibold) : .headline)
                .padding(.horizontal, compact ? 14 : 20)
                .padding(.vertical, compact ? 8 : 12)
                .background(Color.white.opacity(0.16), in: Capsule())
                .foregroundStyle(.white)
                .liveActivitySingleLine(minimumScaleFactor: compact ? 0.72 : 0.8)
        } else {
            Button(intent: StartRecordingLiveActivityIntent()) {
                Label("Record", systemImage: "record.circle")
                    .labelStyle(.titleAndIcon)
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                    .padding(.horizontal, compact ? 14 : 20)
                    .padding(.vertical, compact ? 8 : 12)
                    .background(Color.white, in: Capsule())
                    .foregroundStyle(.black)
                    .liveActivitySingleLine(minimumScaleFactor: compact ? 0.72 : 0.8)
            }
            .buttonStyle(.plain)
        }
    }
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
        if isSegmentActive { return .red }
        return .white
    }

    func activitySymbolName(expanded: Bool) -> String {
        if isSegmentActive { return expanded ? "waveform.circle.fill" : "waveform" }
        if isTranscribing { return expanded ? "hourglass.circle" : "hourglass" }
        return expanded ? "mic.circle" : "mic.fill"
    }
}
