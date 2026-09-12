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
        if snapshot.tiles.isEmpty { setup }
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
                    Text("Fix preset")
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
            : "Edit this widget, or open Vox.md, then Settings > Capture Presets.")
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
                        Text("Capture Presets")
                            .font(.caption.bold())
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: 12))
                    }
                    .presetWidgetBounds("header")
                }
                .accessibilityHint("Open Vox.md, then Settings > Capture Presets to manage the Capture Bar.")
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
                    Text("Capture Presets")
                        .font(.caption2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .presetWidgetBounds("setup-presets")
                } else {
                    Image(systemName: "pin")
                        .font(.system(size: 24))
                        .widgetAccentable()
                        .presetWidgetBounds("setup-icon")
                    Text(snapshot.emptyState == .emptyCaptureBar ? "No available presets" : "Set up Capture Presets")
                        .font(.headline)
                        .lineLimit(family == .systemSmall ? 1 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .presetWidgetBounds("setup-title")
                    Text("Open Vox.md → Settings > Capture Presets")
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
        .accessibilityLabel("Set up Capture Presets")
        .accessibilityHint("Open Vox.md, then Settings > Capture Presets. Pin presets or edit this widget to choose Custom.")
    }

    private func tileVisibleTitle(_ tile: CapturePresetWidgetTile) -> String? {
        if let identity = tile.identity {
            let title = identity.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }
        return tile.presetID == nil ? String(localized: "Choose preset") : String(localized: "Unavailable preset")
    }

    private func tileAccessibilityTitle(_ tile: CapturePresetWidgetTile) -> String {
        tile.identity?.accessibilityName
            ?? tileVisibleTitle(tile)
            ?? String(localized: "Icon-only Capture Preset")
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
        return tile.presetID == nil ? String(localized: "Choose preset") : String(localized: "Unavailable preset")
    }

    private var accessibilityTitle: String {
        tile.identity?.accessibilityName
            ?? title
            ?? String(localized: "Icon-only Capture Preset")
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
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            .presetWidgetBounds("\(tile.id)-tile")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(available ? accessibilityTitle : String(localized: "\(accessibilityTitle), unavailable"))
        .accessibilityHint(available
            ? "Opens Vox.md. Does not send or record."
            : "Edit this widget, or open Vox.md, then Settings > Capture Presets.")
        .accessibilityIdentifier("capture_preset_widget_\(tile.id)")
    }

    private var icon: some View {
        CapturePresetIconView(symbolName: tile.identity?.symbolName ?? "questionmark.square.dashed", emoji: tile.identity?.emoji)
            .font(.system(size: compactText && !large ? 28 : 24))
            .widgetAccentable()
            .presetWidgetBounds("\(tile.id)-icon")
    }
}

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
