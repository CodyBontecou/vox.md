import SwiftUI
import VoxboardShared
import WidgetKit

struct CapturePresetWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: CapturePresetWidgetSnapshot

    var body: some View {
        CapturePresetWidgetView(snapshot: snapshot, family: family)
    }
}

/// Values only. Explicit family permits hosted tests without overriding
/// WidgetKit's read-only environment. Large type changes presentation, never
/// the count, position or expected ID of custom slots.
struct CapturePresetWidgetView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snapshot: CapturePresetWidgetSnapshot
    let family: WidgetFamily

    private var compactText: Bool { dynamicTypeSize >= .xxxLarge }

    static var setupURL: URL {
        var components = URLComponents()
        components.scheme = "voxboard"
        components.host = "capture"
        components.queryItems = [URLQueryItem(name: "source", value: "widget")]
        return components.url!
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: CapturePresetWidgetBounds.coordinateSpace)
    }

    @ViewBuilder
    private var content: some View {
        if family == .accessoryCircular || family == .accessoryRectangular { accessory }
        else if snapshot.tiles.isEmpty { setup }
        else if family == .systemSmall { small }
        else { grid }
    }

    private var small: some View {
        let tile = snapshot.tiles[0]
        let available = tile.availability == .available && tile.captureURL != nil
        return Link(destination: tile.captureURL ?? Self.setupURL) {
            VStack(alignment: .leading, spacing: 8) {
                if compactText && !available {
                    // Fixed-family space cannot fit an icon, name and verbose
                    // repair copy at large type. Keep a legible explicit fix,
                    // with the exact name/repair instructions in accessibility.
                    Text("Fix route")
                        .font(.headline)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                        .presetWidgetBounds("small-fix")
                    Text("Edit widget")
                        .font(.caption2)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                        .presetWidgetBounds("small-guidance")
                } else {
                    CapturePresetIconView(symbolName: tile.identity?.symbolName ?? "questionmark.square.dashed", emoji: tile.identity?.emoji)
                        .font(.system(size: 32)) // Decorative glyph, not squeezed text.
                        .foregroundStyle(available ? capturePresetSignalAccent : Color.secondary)
                        .widgetAccentable()
                        .presetWidgetBounds("small-icon")
                    if !compactText { Spacer(minLength: 0) }
                    if let title = tileVisibleTitle(tile) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(compactText ? 1 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .presetWidgetBounds("small-name")
                    }
                    if !compactText {
                        Text(available ? "Open Capture" : "Fix in Settings")
                            .font(.caption2)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                            .presetWidgetBounds("small-status")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .widgetURL(tile.captureURL ?? Self.setupURL)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(available ? tileAccessibilityTitle(tile) : String(localized: "\(tileAccessibilityTitle(tile)), unavailable"))
        .accessibilityHint(available
            ? "Opens Vox.md. Does not send or record."
            : "Edit this widget, or open Vox.md, then Settings > Routes.")
    }

    /// Lock Screen accessory: the first route (circular), or the first route
    /// plus the following positions (rectangular). Opens the first route.
    @ViewBuilder
    private var accessory: some View {
        let tile = snapshot.tiles.first
        let available = tile.map { $0.availability == .available && $0.captureURL != nil } ?? false
        let url = (available ? tile?.captureURL : nil) ?? Self.setupURL
        let name = tile.flatMap(tileVisibleTitle) ?? String(localized: "Routes")
        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 2) {
                        CapturePresetIconView(
                            symbolName: available ? (tile?.identity?.symbolName ?? "waveform") : "pin",
                            emoji: available ? tile?.identity?.emoji : nil
                        )
                        .font(.system(size: 18, weight: .semibold))
                        .widgetAccentable()
                        Text(available ? name : String(localized: "Routes"))
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 4)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("ROUTES")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .widgetAccentable()
                        .lineLimit(1)
                    Text(available ? name : String(localized: "Set up Routes"))
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    let others = snapshot.tiles.dropFirst()
                        .filter { $0.availability == .available }
                        .compactMap(tileVisibleTitle)
                    if available, !others.isEmpty {
                        Text(others.prefix(3).joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(available ? String(localized: "Open Capture") : String(localized: "Open Vox.md → Settings"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetURL(url)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(available ? (tile.map(tileAccessibilityTitle) ?? name) : String(localized: "Set up Routes"))
        .accessibilityHint(available ? "Opens Vox.md. Does not send or record." : "Open Vox.md, then Settings > Routes.")
    }

    private var grid: some View {
        let large = family == .systemLarge
        let tiles = Array(snapshot.tiles.prefix(large ? 8 : 6))
        return VStack(alignment: .leading, spacing: 6) {
            // Medium remains a six-position grid at large type. No growing
            // header/footer competes with its two rows; each fix is in its slot.
            if large || !compactText {
                Link(destination: Self.setupURL) {
                    HStack {
                        Text("Routes")
                            .font(.caption.bold())
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: 12))
                    }
                    .presetWidgetBounds("header")
                }
                .accessibilityHint("Open Vox.md, then Settings > Routes to manage the Capture Bar.")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: large ? 2 : 3), spacing: 6) {
                ForEach(tiles) { tile in
                    CapturePresetWidgetTileView(tile: tile, large: large, compactText: compactText)
                }
            }
            if large { Spacer(minLength: 0) }
        }
    }

    private var setup: some View {
        Link(destination: Self.setupURL) {
            VStack(alignment: .leading, spacing: 6) {
                if compactText {
                    // At the largest iOS sizes, three text lines exceed the
                    // small family's height. A Settings glyph leaves room for
                    // the two-line destination without shrinking native text.
                    if family == .systemSmall {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20))
                            .accessibilityHidden(true)
                            .presetWidgetBounds("setup-settings-icon")
                    } else {
                        Text("Settings")
                            .font(.caption2)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                            .presetWidgetBounds("setup-settings")
                    }
                    Text("Routes")
                        .font(.caption2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .presetWidgetBounds("setup-presets")
                } else {
                    Image(systemName: "pin")
                        .font(.system(size: 24))
                        .foregroundStyle(capturePresetSignalAccent)
                        .widgetAccentable()
                        .presetWidgetBounds("setup-icon")
                    Text(snapshot.emptyState == .emptyCaptureBar ? "No available routes" : "Set up Routes")
                        .font(.headline)
                        .lineLimit(family == .systemSmall ? 1 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .presetWidgetBounds("setup-title")
                    Text("Open Vox.md → Settings > Routes")
                        .font(.caption2)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .presetWidgetBounds("setup-guidance")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .widgetURL(Self.setupURL)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Set up Routes")
        .accessibilityHint("Open Vox.md, then Settings > Routes. Pin routes or edit this widget to choose Custom.")
    }

    private func tileVisibleTitle(_ tile: CapturePresetWidgetTile) -> String? {
        if let identity = tile.identity {
            let title = identity.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }
        return tile.presetID == nil ? String(localized: "Choose route") : String(localized: "Unavailable route")
    }

    private func tileAccessibilityTitle(_ tile: CapturePresetWidgetTile) -> String {
        tile.identity?.accessibilityName
            ?? tileVisibleTitle(tile)
            ?? String(localized: "Icon-only Route")
    }
}

private struct CapturePresetWidgetTileView: View {
    let tile: CapturePresetWidgetTile
    let large: Bool
    let compactText: Bool

    private var available: Bool { tile.availability == .available && tile.captureURL != nil }
    private var title: String? {
        if let identity = tile.identity {
            let title = identity.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }
        return tile.presetID == nil ? String(localized: "Choose route") : String(localized: "Unavailable route")
    }

    private var accessibilityTitle: String {
        tile.identity?.accessibilityName
            ?? title
            ?? String(localized: "Icon-only Route")
    }

    var body: some View {
        Link(destination: tile.captureURL ?? CapturePresetWidgetView.setupURL) {
            HStack(spacing: 5) {
                if compactText && !large {
                    if available { icon }
                    else {
                        Text("Fix")
                            .font(.caption2)
                            .lineLimit(1)
                            .fixedSize()
                            .presetWidgetBounds("\(tile.id)-fix")
                    }
                } else {
                    icon
                    if let title {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(compactText && !available ? String(localized: "Fix: \(title)") : title)
                                .font(large ? (compactText ? .caption2 : .subheadline) : .caption2)
                                .fontWeight(.semibold)
                                .lineLimit(large && !compactText ? 2 : 1)
                                .fixedSize(horizontal: false, vertical: true)
                                .presetWidgetBounds("\(tile.id)-name")
                            if !available && !compactText {
                                Text("Fix")
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .presetWidgetBounds("\(tile.id)-fix")
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: large ? 56 : 44, alignment: compactText && !large ? .center : .leading)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            )
            .presetWidgetBounds("\(tile.id)-tile")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(available ? accessibilityTitle : String(localized: "\(accessibilityTitle), unavailable"))
        .accessibilityHint(available
            ? "Opens Vox.md. Does not send or record."
            : "Edit this widget, or open Vox.md, then Settings > Routes.")
        .accessibilityIdentifier("capture_preset_widget_\(tile.id)")
    }

    private var icon: some View {
        CapturePresetIconView(symbolName: tile.identity?.symbolName ?? "questionmark.square.dashed", emoji: tile.identity?.emoji)
            .font(.system(size: compactText && !large ? 28 : 24))
            .foregroundStyle(available ? capturePresetSignalAccent : Color.secondary)
            .widgetAccentable()
            .presetWidgetBounds("\(tile.id)-icon")
    }
}

/// Signal accent (#2F3BE8). File-local because this view also compiles
/// into hosted tests, and the extension does not compile GeistTheme.
private let capturePresetSignalAccent = Color(red: 47 / 255, green: 59 / 255, blue: 232 / 255)

/// Bounds of the actual rendered labels/glyphs/tiles, not merely the host's
/// nonzero frame. Hosted tests can fail on overflow with normal SwiftUI layout.
struct CapturePresetWidgetBounds: PreferenceKey {
    static let coordinateSpace = "capture-preset-widget-content"
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private extension View {
    func presetWidgetBounds(_ id: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: CapturePresetWidgetBounds.self, value: [
                    id: proxy.frame(in: .named(CapturePresetWidgetBounds.coordinateSpace)),
                ])
            }
        }
    }
}
