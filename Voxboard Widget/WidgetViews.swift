import SwiftUI
import WidgetKit

// MARK: - Entry View (dispatches by family)

struct VoxboardWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: VoxboardWidgetEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularWidgetView(entry: entry)
        case .accessoryRectangular:
            RectangularWidgetView(entry: entry)
        case .systemSmall:
            SmallWidgetView(entry: entry)
        default:
            CircularWidgetView(entry: entry)
        }
    }
}

// MARK: - Signal palette (extension-local; GeistTheme is app-only)

private enum SignalWidget {
    static let accent = Color(red: 47 / 255, green: 59 / 255, blue: 232 / 255)   // #2F3BE8
    static let red = Color(red: 240 / 255, green: 71 / 255, blue: 74 / 255)      // #F0474A
    static let muted = Color(red: 94 / 255, green: 94 / 255, blue: 90 / 255)     // #5E5E5A
    static let mutedDark = Color(red: 154 / 255, green: 154 / 255, blue: 149 / 255) // #9A9A95
}

// MARK: - Lock Screen: Circular

struct CircularWidgetView: View {
    let entry: VoxboardWidgetEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: entry.isQuickRecordEnabled ? (entry.isListening ? "mic.fill" : "mic") : "mic.slash")
                    .font(.system(size: 20, weight: .semibold))
                    .widgetAccentable()
                    .foregroundStyle(entry.isQuickRecordEnabled ? .primary : .secondary)
                if entry.isQuickRecordEnabled && entry.isListening {
                    Circle()
                        .frame(width: 4, height: 4)
                        .widgetAccentable()
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

// MARK: - Lock Screen: Rectangular

struct RectangularWidgetView: View {
    let entry: VoxboardWidgetEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 18, weight: .semibold))
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text("Vox.md")
                    .font(SignalWidgetFont.sans(11, .semibold))
                    .textCase(.uppercase)
                    .widgetAccentable()
                Text(entry.isQuickRecordEnabled
                     ? (entry.isListening ? String(localized: "Listening") : String(localized: "Tap to record"))
                     : String(localized: "Disabled"))
                    .font(SignalWidgetFont.sans(14, .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Home Screen: Small

struct SmallWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: VoxboardWidgetEntry

    private var isLive: Bool { entry.isQuickRecordEnabled && entry.isListening }
    private var muted: Color { colorScheme == .dark ? SignalWidget.mutedDark : SignalWidget.muted }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isLive ? SignalWidget.accent : muted)
                    .frame(width: 6, height: 6)
                Text(entry.isQuickRecordEnabled
                     ? (entry.isListening ? String(localized: "Listening") : String(localized: "Ready"))
                     : String(localized: "Disabled"))
                    .font(SignalWidgetFont.mono(11, medium: true))
                    .textCase(.uppercase)
                    .foregroundStyle(isLive ? Color.primary : muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 8)
            HStack {
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .fill(entry.isQuickRecordEnabled ? SignalWidget.red.opacity(0.14) : muted.opacity(0.12))
                        .frame(width: 76, height: 76)
                    Circle()
                        .fill(entry.isQuickRecordEnabled ? SignalWidget.red : muted.opacity(0.5))
                        .frame(width: 58, height: 58)
                    Image(systemName: entry.isQuickRecordEnabled ? "mic.fill" : "mic.slash")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .widgetAccentable()
                .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 8)
            Text(entry.isQuickRecordEnabled
                 ? String(localized: "Tap to Record")
                 : String(localized: "Enable in Settings"))
                .font(SignalWidgetFont.sans(13, .semibold))
                .foregroundStyle(entry.isQuickRecordEnabled ? Color.primary : muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Previews

#Preview("Circular", as: .accessoryCircular) {
    VoxboardRecordWidget()
} timeline: {
    VoxboardWidgetEntry(date: .now, isListening: false, isQuickRecordEnabled: true)
    VoxboardWidgetEntry(date: .now, isListening: true, isQuickRecordEnabled: true)
    VoxboardWidgetEntry(date: .now, isListening: false, isQuickRecordEnabled: false)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    VoxboardRecordWidget()
} timeline: {
    VoxboardWidgetEntry(date: .now, isListening: false, isQuickRecordEnabled: true)
    VoxboardWidgetEntry(date: .now, isListening: true, isQuickRecordEnabled: true)
    VoxboardWidgetEntry(date: .now, isListening: false, isQuickRecordEnabled: false)
}

#Preview("Small", as: .systemSmall) {
    VoxboardRecordWidget()
} timeline: {
    VoxboardWidgetEntry(date: .now, isListening: false, isQuickRecordEnabled: true)
    VoxboardWidgetEntry(date: .now, isListening: true, isQuickRecordEnabled: true)
    VoxboardWidgetEntry(date: .now, isListening: false, isQuickRecordEnabled: false)
}
