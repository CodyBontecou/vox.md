import AppIntents
import SwiftUI
import WidgetKit

private enum WatchWidgetGeist {
    // Signal semantic colors (dark/watch variants).
    /// Indigo tint for glyphs and text on black (#8A8FFF).
    static let active = Color(red: 138 / 255, green: 143 / 255, blue: 255 / 255)
    /// Indigo ring for the idle record mark (#2F3BE8).
    static let accentRing = Color(red: 47 / 255, green: 59 / 255, blue: 232 / 255)
    /// Recording red (#F0474A).
    static let error = Color(red: 240 / 255, green: 71 / 255, blue: 74 / 255)
    static let disc = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)   // #1C1C1E
    static let muted = Color(red: 154 / 255, green: 154 / 255, blue: 149 / 255) // #9A9A95

    static func label(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

struct VoxboardWatchRecordEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchRecordingSnapshot
}

struct VoxboardWatchRecordConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Record voice note"
    static let description = IntentDescription("Start a local Watch recording and sync it to Vox.md.")
}

struct VoxboardWatchRecordProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> VoxboardWatchRecordEntry {
        VoxboardWatchRecordEntry(
            date: .now,
            snapshot: WatchRecordingSnapshot(phase: .idle, isQuickRecordEnabled: true)
        )
    }

    func snapshot(
        for configuration: VoxboardWatchRecordConfigurationIntent,
        in context: Context
    ) async -> VoxboardWatchRecordEntry {
        VoxboardWatchRecordEntry(date: .now, snapshot: currentSnapshot())
    }

    func timeline(
        for configuration: VoxboardWatchRecordConfigurationIntent,
        in context: Context
    ) async -> Timeline<VoxboardWatchRecordEntry> {
        let entry = VoxboardWatchRecordEntry(date: .now, snapshot: currentSnapshot())
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60)))
    }

    func recommendations() -> [AppIntentRecommendation<VoxboardWatchRecordConfigurationIntent>] {
        [
            AppIntentRecommendation(
                intent: VoxboardWatchRecordConfigurationIntent(),
                description: Text("Record voice note")
            )
        ]
    }

    private func currentSnapshot() -> WatchRecordingSnapshot {
        WatchLocalSnapshotStore.load() ?? WatchPhoneBridge.cachedSnapshot()
    }
}

struct VoxboardWatchRecordWidget: Widget {
    let kind = "VoxboardWatchRecordWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: VoxboardWatchRecordConfigurationIntent.self,
            provider: VoxboardWatchRecordProvider()
        ) { entry in
            VoxboardWatchRecordWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(Self.tapURL(for: entry.snapshot))
        }
        .configurationDisplayName("Record voice note")
        .description("Start a voice note from your Apple Watch face and sync it to Vox.md on iPhone.")
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
        #else
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        #endif
    }

    /// Idle taps start recording straight to the published route; taps while
    /// recording open the in-progress recording.
    static func tapURL(for snapshot: WatchRecordingSnapshot) -> URL {
        switch snapshot.phase {
        case .recording, .paused:
            return WatchRecordingDeepLink.toggleURL
        default:
            return WatchRecordingDeepLink.startURL(routeID: snapshot.selectedPresetID)
        }
    }
}

struct VoxboardWatchRecordWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VoxboardWatchRecordEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            inline
        case .accessoryCorner:
            corner
        default:
            circular
        }
    }

    // Keep face-facing complication previews vector-drawn; oversized raster assets
    // can fail to render/select on physical Apple Watch hardware.
    private var circular: some View {
        RecordIntentButton {
            GeometryReader { proxy in
                let isWidePickerRow = proxy.size.width > proxy.size.height * 1.35
                let markSize = min(proxy.size.height * 0.58, 31)

                if isWidePickerRow {
                    HStack(spacing: max(proxy.size.height * 0.10, 8)) {
                        ZStack {
                            AccessoryWidgetBackground()
                            VoxboardComplicationMark(phase: entry.snapshot.phase)
                                .frame(width: markSize, height: markSize)
                        }
                        .frame(width: proxy.size.height, height: proxy.size.height)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(routeName ?? String(localized: "Record voice note"))
                                .font(WatchWidgetGeist.label(12, weight: .bold))
                                .widgetAccentable()
                                .lineLimit(1)
                                .minimumScaleFactor(0.68)
                            Text("Tap to speak")
                                .font(WatchWidgetGeist.label(10, weight: .regular))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.horizontal, max(proxy.size.height * 0.08, 6))
                } else {
                    ZStack {
                        AccessoryWidgetBackground()
                        if entry.snapshot.shouldShowTimer, let started = entry.snapshot.recordingStartedAt {
                            // Signal "while recording": red ring + mono timer.
                            Circle()
                                .strokeBorder(WatchWidgetGeist.error, lineWidth: 2)
                                .widgetAccentable()
                                .padding(2)
                            Text(Date(timeIntervalSince1970: started), style: .timer)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .padding(.horizontal, 6)
                        } else {
                            VoxboardComplicationMark(phase: entry.snapshot.phase)
                                .frame(width: markSize, height: markSize)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .buttonStyle(.plain)
        .widgetLabel {
            Text(routeName ?? String(localized: "Record note"))
        }
    }

    /// Selected / last-used route published by the Watch app.
    private var routeName: String? {
        guard let name = entry.snapshot.selectedPresetName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty else { return nil }
        return name
    }

    private var isIdle: Bool {
        switch entry.snapshot.phase {
        case .idle, .listening, .unavailable: return true
        default: return false
        }
    }

    /// Idle with nothing queued, no timer and no paused take: the two-line
    /// "Tap to speak" state.
    private var isIdleReady: Bool {
        isIdle && entry.snapshot.queuedCount == 0
            && !entry.snapshot.shouldShowTimer && entry.snapshot.pausedDuration == nil
    }

    /// Signal rectangular header: "VOX.MD · <ROUTE>" (just "VOX.MD" for queue).
    private var rectangularHeader: String {
        if let routeName, !(isIdle && entry.snapshot.queuedCount > 0) {
            return "Vox.md · \(routeName)"
        }
        return "Vox.md"
    }

    private var rectangular: some View {
        RecordIntentButton {
            HStack(spacing: 8) {
                VoxboardComplicationMark(phase: entry.snapshot.phase)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 5, height: 5)
                            .widgetAccentable()
                        Text(rectangularHeader)
                            .font(WatchWidgetGeist.label(11, weight: .semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(WatchWidgetGeist.active)
                            .widgetAccentable()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    if isIdleReady {
                        // Idle board: two lines, "VOX.MD · <ROUTE>" and
                        // "Tap to speak".
                        Text("Tap to speak")
                            .font(WatchWidgetGeist.label(13, weight: .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text(rectangularTitle)
                            .font(WatchWidgetGeist.label(14, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        subtitleText
                            .font(WatchWidgetGeist.label(12, weight: .regular))
                            .foregroundStyle(WatchWidgetGeist.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private var inline: some View {
        RecordIntentButton {
            Label {
                if entry.snapshot.shouldShowTimer, let started = entry.snapshot.recordingStartedAt {
                    Text(Date(timeIntervalSince1970: started), style: .timer)
                } else if let pausedDuration = entry.snapshot.pausedDuration {
                    Text("Paused \(formattedDuration(pausedDuration))")
                } else if isIdle, entry.snapshot.queuedCount == 0, let routeName {
                    Text("\(routeName) · tap to speak")
                } else {
                    Text(inlineTitle)
                }
            } icon: {
                Image(systemName: isIdle && entry.snapshot.queuedCount == 0 ? "circle.fill" : stateSymbolName)
            }
        }
        .buttonStyle(.plain)
    }

    private var corner: some View {
        RecordIntentButton {
            VoxboardComplicationMark(phase: entry.snapshot.phase)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .widgetLabel {
            Text(cornerLabel)
        }
    }

    @ViewBuilder
    private var subtitleText: some View {
        if entry.snapshot.shouldShowTimer, let started = entry.snapshot.recordingStartedAt {
            Text(Date(timeIntervalSince1970: started), style: .timer)
                .fontDesign(.monospaced)
                .monospacedDigit()
        } else if let pausedDuration = entry.snapshot.pausedDuration {
            Text("Paused · \(formattedDuration(pausedDuration))")
                .fontDesign(.monospaced)
                .monospacedDigit()
        } else if isIdle, entry.snapshot.queuedCount > 0 {
            Text(queueBreakdown)
        } else if isIdle {
            Text("Tap to speak")
        } else {
            Text(entry.snapshot.subtitle)
        }
    }

    private var rectangularTitle: String {
        if isIdle, entry.snapshot.queuedCount > 0 {
            return entry.snapshot.queuedCount == 1
                ? String(localized: "1 waiting for iPhone")
                : String(localized: "\(entry.snapshot.queuedCount) waiting for iPhone")
        }
        if isIdle {
            return routeName ?? String(localized: "Record to Vox.md")
        }
        return inlineTitle
    }

    /// "Journal · Inbox · saved on Watch".
    private var queueBreakdown: String {
        let names = entry.snapshot.queuedRouteNames
        guard !names.isEmpty else { return String(localized: "Saved on Watch") }
        return names.joined(separator: " · ") + " · " + String(localized: "saved on Watch")
    }

    private var stateSymbolName: String {
        entry.snapshot.actionSymbol
    }

    private var stateColor: Color {
        switch entry.snapshot.phase {
        case .recording, .error, .unavailable:
            return WatchWidgetGeist.error
        case .paused, .syncing, .transcribing, .delivering, .pending:
            return WatchWidgetGeist.active
        case .idle, .listening:
            return WatchWidgetGeist.active
        }
    }

    private var inlineTitle: String {
        switch entry.snapshot.phase {
        case .recording:
            return String(localized: "Recording")
        case .paused:
            return String(localized: "Paused")
        case .syncing:
            return String(localized: "Syncing")
        case .transcribing:
            return String(localized: "Transcribing")
        case .delivering:
            return String(localized: "Saving")
        case .pending:
            return String(localized: "Synced")
        case .error:
            return String(localized: "Check Vox.md")
        case .unavailable:
            return String(localized: "Open iPhone")
        case .idle, .listening:
            if entry.snapshot.queuedCount > 0 {
                return entry.snapshot.queuedCount == 1
                    ? String(localized: "1 waiting for iPhone")
                    : String(localized: "\(entry.snapshot.queuedCount) waiting for iPhone")
            }
            return routeName.map { String(localized: "\($0) · tap to speak") }
                ?? String(localized: "Record to Vox.md")
        }
    }

    private var cornerLabel: String {
        switch entry.snapshot.phase {
        case .recording, .paused:
            return String(localized: "Stop")
        case .syncing:
            return String(localized: "Sync")
        case .transcribing:
            return String(localized: "Text")
        case .delivering:
            return String(localized: "Save")
        case .pending:
            return String(localized: "Sent")
        case .error, .unavailable:
            return String(localized: "Open")
        default:
            return entry.snapshot.queuedCount > 0
                ? String(localized: "\(entry.snapshot.queuedCount) waiting")
                : (routeName ?? String(localized: "Speak"))
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Signal record mark: a dark disc with a phase-colored ring (indigo idle,
/// red recording/error, indigo tint while syncing) around a red record dot.
private struct VoxboardComplicationMark: View {
    let phase: WatchRecordingPhase

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let ring = max(side * 0.06, 1.5)

            ZStack {
                Circle()
                    .fill(WatchWidgetGeist.disc)
                Circle()
                    .strokeBorder(ringColor, lineWidth: ring)
                    .widgetAccentable()
                Circle()
                    .fill(dotColor)
                    .frame(width: side * dotFraction, height: side * dotFraction)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var ringColor: Color {
        switch phase {
        case .recording, .error, .unavailable:
            return WatchWidgetGeist.error
        case .paused, .syncing, .transcribing, .delivering, .pending:
            return WatchWidgetGeist.active
        case .idle, .listening:
            return WatchWidgetGeist.accentRing
        }
    }

    private var dotColor: Color {
        switch phase {
        case .paused, .syncing, .transcribing, .delivering, .pending:
            return WatchWidgetGeist.active
        default:
            return WatchWidgetGeist.error
        }
    }

    private var dotFraction: CGFloat {
        switch phase {
        case .recording: return 0.34
        default: return 0.28
        }
    }
}

private struct RecordIntentButton<LabelView: View>: View {
    @ViewBuilder let label: () -> LabelView

    var body: some View {
        label()
    }
}

#Preview("Circular", as: .accessoryCircular) {
    VoxboardWatchRecordWidget()
} timeline: {
    VoxboardWatchRecordEntry(date: .now, snapshot: WatchRecordingSnapshot(phase: .idle, isQuickRecordEnabled: true))
    VoxboardWatchRecordEntry(date: .now, snapshot: WatchRecordingSnapshot(phase: .recording, isQuickRecordEnabled: true, recordingStartedAt: Date().timeIntervalSince1970))
}

#Preview("Rectangular", as: .accessoryRectangular) {
    VoxboardWatchRecordWidget()
} timeline: {
    VoxboardWatchRecordEntry(date: .now, snapshot: WatchRecordingSnapshot(phase: .idle, isQuickRecordEnabled: true))
    VoxboardWatchRecordEntry(date: .now, snapshot: WatchRecordingSnapshot(phase: .transcribing, isQuickRecordEnabled: true))
}
