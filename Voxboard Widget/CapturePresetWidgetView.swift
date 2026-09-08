import SwiftUI
import VoxboardShared
import WidgetKit

/// Presentation receives only timeline values. No store/defaults reads, routing
/// mutation, or globally selected preset participates in a rendered tile.
struct CapturePresetWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: CapturePresetWidgetSnapshot

    var body: some View {
        CapturePresetWidgetView(snapshot: snapshot, family: family)
    }
}

/// Explicit family input also permits real offscreen/hosted rendering without
/// trying to override WidgetKit's read-only widgetFamily environment value.
struct CapturePresetWidgetView: View {
    let snapshot: CapturePresetWidgetSnapshot
    let family: WidgetFamily

    static var setupURL: URL {
        var components = URLComponents()
        components.scheme = "voxboard"
        components.host = "capture"
        components.queryItems = [URLQueryItem(name: "source", value: "widget")]
        return components.url!
    }

    var body: some View {
        if snapshot.tiles.isEmpty {
            setup
        } else if family == .systemSmall {
            small
        } else {
            grid
        }
    }

    private var small: some View {
        // First means first, even when Custom's first slot is empty or stale.
        let tile = snapshot.tiles[0]
        return Link(destination: tile.captureURL ?? Self.setupURL) {
            VStack(alignment: .leading, spacing: 6) {
                icon(tile)
                    .font(.largeTitle)
                Spacer(minLength: 0)
                Text(tileTitle(tile))
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Text(tile.availability == .available && tile.captureURL != nil ? "Open Capture" : "Unavailable — edit widget or open Settings > Capture Presets")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .widgetURL(tile.captureURL ?? Self.setupURL)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle(tile))
        .accessibilityHint("Opens Vox.md. Does not send or record.")
    }

    private var grid: some View {
        let large = family == .systemLarge
        let tiles = Array(snapshot.tiles.prefix(large ? 8 : 6))
        return VStack(alignment: .leading, spacing: 6) {
            Link(destination: Self.setupURL) {
                HStack {
                    Text("Capture Presets").font(.caption.bold())
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.caption2)
                }
            }
            .accessibilityHint("Open Vox.md, then Settings > Capture Presets to manage the Capture Bar.")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: large ? 2 : 3), spacing: 6) {
                ForEach(tiles) { tile in
                    CapturePresetWidgetTileView(tile: tile, showsMoreName: large)
                }
            }
            if snapshot.tiles.contains(where: { $0.availability != .available || $0.captureURL == nil }) {
                Text("Unavailable? Edit widget or open Settings > Capture Presets.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            if large { Spacer(minLength: 0) }
        }
    }

    private var setup: some View {
        Link(destination: Self.setupURL) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "pin")
                    .font(.title2)
                    .widgetAccentable()
                Text(snapshot.emptyState == .emptyCaptureBar ? "No pinned presets" : "Set up Capture Presets")
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Text("Open Vox.md → Settings > Capture Presets. Pin presets, or edit this widget to choose Custom.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .widgetURL(Self.setupURL)
    }

    private func icon(_ tile: CapturePresetWidgetTile) -> some View {
        CapturePresetIconView(symbolName: tile.identity?.symbolName ?? "questionmark.square.dashed", emoji: tile.identity?.emoji)
            .widgetAccentable()
    }

    private func tileTitle(_ tile: CapturePresetWidgetTile) -> String {
        tile.identity?.name ?? (tile.presetID == nil ? String(localized: "Choose preset") : String(localized: "Unavailable preset"))
    }

    private func accessibilityTitle(_ tile: CapturePresetWidgetTile) -> String {
        if tile.availability == .available && tile.captureURL != nil { return tileTitle(tile) }
        return String(localized: "\(tileTitle(tile)), unavailable. Edit widget or open Settings, Capture Presets.")
    }
}

private struct CapturePresetWidgetTileView: View {
    let tile: CapturePresetWidgetTile
    let showsMoreName: Bool

    private var available: Bool { tile.availability == .available && tile.captureURL != nil }
    private var title: String {
        tile.identity?.name ?? (tile.presetID == nil ? String(localized: "Choose preset") : String(localized: "Unavailable preset"))
    }

    var body: some View {
        Link(destination: tile.captureURL ?? CapturePresetWidgetView.setupURL) {
            HStack(spacing: 5) {
                CapturePresetIconView(symbolName: tile.identity?.symbolName ?? "questionmark.square.dashed", emoji: tile.identity?.emoji)
                    .font(showsMoreName ? .title2 : .title3)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(showsMoreName ? .subheadline : .caption2)
                        .fontWeight(.semibold)
                        .lineLimit(showsMoreName ? 2 : 1)
                        .minimumScaleFactor(0.7)
                    if !available {
                        Text("Unavailable")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: showsMoreName ? 56 : 44, alignment: .leading)
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(available ? title : String(localized: "\(title), unavailable. Edit widget or open Settings, Capture Presets."))
        .accessibilityHint("Opens Vox.md. Does not send or record.")
        .accessibilityIdentifier("capture_preset_widget_\(tile.id)")
    }
}
