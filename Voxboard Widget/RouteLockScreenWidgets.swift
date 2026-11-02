import AppIntents
import SwiftUI
import VoxboardCaptureCore
import VoxboardShared
import WidgetKit

// Lock Screen accessories bound to one Route: "Speak to <Route>" (circular),
// "<ROUTE> · TODAY" (rectangular), and "Scan to <Route>" (circular).

// MARK: - Configuration

struct RouteAccessoryWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Route"
    static let description = IntentDescription("Choose the Route this Lock Screen widget uses. Leave empty to follow the selected Route.")

    @Parameter(title: "Route", description: "Recordings, scans and the Today summary use this Route.")
    var route: CapturePresetWidgetEntity?

    init() {}

    init(route: CapturePresetWidgetEntity?) {
        self.route = route
    }
}

// MARK: - Entry

struct RouteAccessoryEntry: TimelineEntry {
    struct TodaySummary: Equatable {
        /// Most recent delivery's note title, newest first.
        var latestTitle: String?
        var count: Int
    }

    let date: Date
    /// The route this entry targets; nil when no route can be resolved.
    let routeID: String?
    let identity: CapturePresetWidgetIdentity?
    let today: TodaySummary?

    var isAvailable: Bool { identity?.isEnabled == true && routeID != nil }

    var displayName: String {
        guard let identity else { return String(localized: "Route") }
        return identity.name.isEmpty ? identity.accessibilityName : identity.name
    }

    var symbolName: String {
        let symbol = identity?.symbolName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return symbol.isEmpty ? "waveform" : symbol
    }

    static func placeholder(name: String, today: TodaySummary? = nil) -> Self {
        Self(date: .now, routeID: nil, identity: nil, today: today, placeholderName: name)
    }

    private let placeholderName: String?

    init(
        date: Date,
        routeID: String?,
        identity: CapturePresetWidgetIdentity?,
        today: TodaySummary?,
        placeholderName: String? = nil
    ) {
        self.date = date
        self.routeID = routeID
        self.identity = identity
        self.today = today
        self.placeholderName = placeholderName
    }

    var visibleName: String { placeholderName ?? displayName }
}

// MARK: - URLs

enum RouteAccessoryLinks {
    static func capture(routeID: String?, action: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "voxboard"
        components.host = "capture"
        var items = [URLQueryItem(name: "source", value: "widget")]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        if let routeID, isRoundTrippable(routeID) {
            items.append(URLQueryItem(name: "preset", value: routeID))
        }
        components.queryItems = items
        return components.url!
    }

    /// One-shot recording for the route. Falls back to opening Capture when the
    /// Lock Screen Record setting is off (the app ignores widget-record then).
    static func record(routeID: String?) -> URL {
        guard VoxboardWidgetProvider.readQuickRecordEnabled() else {
            return capture(routeID: routeID)
        }
        var components = URLComponents()
        components.scheme = "voxboard"
        components.host = "widget-record"
        if let routeID, isRoundTrippable(routeID) {
            components.queryItems = [URLQueryItem(name: "flowId", value: routeID)]
        }
        return components.url!
    }

    private static func isRoundTrippable(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 160 && id == id.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Provider

struct RouteAccessoryProvider: AppIntentTimelineProvider {
    /// The rectangular widget also reads today's delivery history.
    let includesToday: Bool

    func placeholder(in context: Context) -> RouteAccessoryEntry {
        .placeholder(
            name: includesToday ? "Tasks" : "Inbox",
            today: includesToday ? .init(latestTitle: "Book flights for Lisbon", count: 3) : nil
        )
    }

    func snapshot(for configuration: RouteAccessoryWidgetConfiguration, in context: Context) async -> RouteAccessoryEntry {
        let entry = await entry(for: configuration)
        if context.isPreview, entry.identity == nil { return placeholder(in: context) }
        return entry
    }

    func timeline(for configuration: RouteAccessoryWidgetConfiguration, in context: Context) async -> Timeline<RouteAccessoryEntry> {
        let entry = await entry(for: configuration)
        // Refresh at midnight so "Today" resets, and periodically as a recovery
        // path; the app also reloads this kind when a recording is delivered.
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: entry.date.addingTimeInterval(86_400))
        let next = min(midnight, entry.date.addingTimeInterval(includesToday ? 1_800 : 3_600))
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func entry(for configuration: RouteAccessoryWidgetConfiguration) async -> RouteAccessoryEntry {
        let defaults = CapturePresetWidgetEntityQuery.sharedDefaults()
        let identities = CapturePresetWidgetCatalog.identities(
            profiles: CapturePresetQuickAccessStore.loadAuthoritativeProfiles(defaults: defaults) ?? []
        )
        let routeID = configuration.route?.id
            ?? CapturePresetProfileStore.selectedProfileID(defaults: defaults)
            ?? identities.first(where: \.isEnabled)?.id
        let identity = routeID.flatMap { id in identities.first { $0.id == id } }
        let today = includesToday ? await Self.todaySummary(routeID: routeID) : nil
        return RouteAccessoryEntry(date: .now, routeID: routeID, identity: identity, today: today)
    }

    /// Delivered captures for the route since local midnight. The item text
    /// comes from the small Route Today snapshot written at delivery (first
    /// lines only); without it, items are titled by their note file.
    static func todaySummary(routeID: String?, now: Date = .now) async -> RouteAccessoryEntry.TodaySummary {
        guard let routeID, let url = AppConstants.captureHistoryURL else {
            return .init(latestTitle: nil, count: 0)
        }
        let snapshotRoute = CaptureRouteTodaySnapshot.load(historyFileURL: url)?.route(routeID, now: now)
        guard FileManager.default.fileExists(atPath: url.path),
              let records = try? await CaptureHistoryStore(fileURL: url).list() else {
            if let snapshotRoute, let first = snapshotRoute.items.first {
                return .init(latestTitle: first.firstLine, count: snapshotRoute.count)
            }
            return .init(latestTitle: nil, count: 0)
        }
        let calendar = Calendar.current
        let todays = records
            .filter { $0.outcome == .delivered && $0.voxID == routeID }
            .filter { calendar.isDate($0.deliveredAt ?? $0.createdAt, inSameDayAs: now) }
            .sorted { ($0.deliveredAt ?? $0.createdAt) > ($1.deliveredAt ?? $1.createdAt) }
        let latest = todays.first.flatMap { record -> String? in
            if let line = snapshotRoute?.items.first(where: { $0.requestID == record.requestID })?.firstLine {
                return line
            }
            if let path = record.relativeNotePath {
                let name = (path as NSString).lastPathComponent
                let stem = (name as NSString).deletingPathExtension
                return stem.isEmpty ? name : stem
            }
            let destination = record.destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
            return destination.isEmpty ? nil : destination
        }
        return .init(latestTitle: latest, count: todays.count)
    }
}

// MARK: - Widgets

struct RouteSpeakWidget: Widget {
    let kind = VoxboardRouteWidgetKinds.speak

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: RouteAccessoryWidgetConfiguration.self,
            provider: RouteAccessoryProvider(includesToday: false)
        ) { entry in
            RouteSpeakAccessoryView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(RouteAccessoryLinks.record(routeID: entry.routeID))
        }
        .configurationDisplayName("Speak to Route")
        .description("Start a recording that is delivered to the chosen Route.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct RouteTodayWidget: Widget {
    let kind = VoxboardRouteWidgetKinds.today

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: RouteAccessoryWidgetConfiguration.self,
            provider: RouteAccessoryProvider(includesToday: true)
        ) { entry in
            RouteTodayAccessoryView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(RouteAccessoryLinks.capture(routeID: entry.routeID))
        }
        .configurationDisplayName("Route Today")
        .description("What you sent to a Route today. Tap to open it.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct RouteScanWidget: Widget {
    let kind = VoxboardRouteWidgetKinds.scan

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: RouteAccessoryWidgetConfiguration.self,
            provider: RouteAccessoryProvider(includesToday: false)
        ) { entry in
            RouteScanAccessoryView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(RouteAccessoryLinks.capture(routeID: entry.routeID, action: "scan"))
        }
        .configurationDisplayName("Scan to Route")
        .description("Scan a document straight into the chosen Route.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Views

/// Lock Screen glass tile: a mic (or scan) glyph over the route name.
private struct RouteCircleAccessory: View {
    let systemImage: String
    let label: String

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .widgetAccentable()
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct RouteSpeakAccessoryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RouteAccessoryEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("Speak to \(entry.visibleName)", systemImage: "mic.fill")
            default:
                RouteCircleAccessory(systemImage: "mic", label: entry.visibleName)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speak to \(entry.visibleName)")
        .accessibilityHint("Opens Vox.md and starts recording to this Route.")
    }
}

struct RouteScanAccessoryView: View {
    let entry: RouteAccessoryEntry

    var body: some View {
        RouteCircleAccessory(systemImage: "viewfinder", label: String(localized: "Scan"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Scan to \(entry.visibleName)")
            .accessibilityHint("Opens the document scanner for this Route.")
    }
}

struct RouteTodayAccessoryView: View {
    let entry: RouteAccessoryEntry

    var body: some View {
        let summary = entry.today ?? .init(latestTitle: nil, count: 0)
        // Lock Screen board: the summary sits on the same glass tile as the
        // circular Speak/Scan accessories.
        ZStack {
            AccessoryWidgetBackground()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            content(summary)
                .padding(.horizontal, 12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this Route in Vox.md.")
    }

    private func content(_ summary: RouteAccessoryEntry.TodaySummary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(entry.visibleName.uppercased()) · TODAY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .widgetAccentable()
            if let title = summary.latestTitle, summary.count > 0 {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if summary.count > 1 {
                    Text("+\(summary.count - 1) more")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Nothing yet")
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text(entry.isAvailable || entry.identity == nil ? "Tap to capture" : "Route unavailable")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
