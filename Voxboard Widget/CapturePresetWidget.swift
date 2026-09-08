import AppIntents
import SwiftUI
import VoxboardCaptureCore
import WidgetKit

struct CapturePresetWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: CapturePresetWidgetSnapshot
}

struct CapturePresetWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CapturePresetWidgetEntry {
        CapturePresetWidgetEntry(
            date: .now,
            snapshot: CapturePresetWidgetSnapshot(selection: .followCaptureBar, pins: .absent, profiles: [])
        )
    }

    func snapshot(for configuration: CapturePresetWidgetConfiguration, in context: Context) async -> CapturePresetWidgetEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: CapturePresetWidgetConfiguration, in context: Context) async -> Timeline<CapturePresetWidgetEntry> {
        let entry = entry(for: configuration)
        // Targeted host requests improve freshness; this is a recovery refresh,
        // not a guarantee of instant cross-process propagation or exact timing.
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(900)))
    }

    private func entry(for configuration: CapturePresetWidgetConfiguration) -> CapturePresetWidgetEntry {
        let selection = configuration.selection
        return CapturePresetWidgetEntry(
            date: .now,
            snapshot: .load(selection: selection, defaults: CapturePresetWidgetEntityQuery.sharedDefaults())
        )
    }
}

struct CapturePresetWidget: Widget {
    let kind = CapturePresetWidgetReload.kind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: CapturePresetWidgetConfiguration.self,
            provider: CapturePresetWidgetProvider()
        ) { entry in
            CapturePresetWidgetEntryView(snapshot: entry.snapshot)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Capture Presets")
        .description("Open a preset without sending or recording. Follow the Capture Bar or choose six ordered custom slots; small shows the first position.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
