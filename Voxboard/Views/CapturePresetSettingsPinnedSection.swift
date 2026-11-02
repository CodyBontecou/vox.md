import SwiftUI
import VoxboardShared

/// Fallback row for a stored pin whose editable preset is temporarily missing.
/// Keeping it in the stored-ID list preserves exact native move offsets and
/// gives the user a direct recovery action instead of silently dropping it.
struct CapturePresetSettingsPinnedRow: View {
    let id: String
    let profile: CapturePresetProfile?
    let unpin: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        layout {
            HStack(spacing: 12) {
                CapturePresetIconView(symbolName: profile?.symbolName ?? "questionmark.square", emoji: profile?.emoji)
                    .foregroundStyle(Geist.muted)
                    .frame(width: 40, height: 40)
                    .background(Geist.well, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.custom("Geist-SemiBold", size: 17, relativeTo: .body))
                        .foregroundStyle(profile?.visibleName == nil ? Geist.muted : Geist.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if profile == nil {
                        Text("Unavailable — unpin or reload")
                            .font(Geist.mono(size: 11.5, relativeTo: .caption))
                            .foregroundStyle(Geist.warning)
                    } else if profile?.isEnabled == false {
                        Text("Hidden until enabled")
                            .font(Geist.mono(size: 11.5, relativeTo: .caption))
                            .foregroundStyle(Geist.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("capture_preset_pinned_name_\(id)")

            CapturePresetSettingsPinButton(
                accessibilityID: "capture_preset_pinned_unpin_\(id)", name: name, isPinned: true, action: unpin
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture_preset_pinned_row_\(id)")
    }

    private var name: String { profile.map { $0.visibleName ?? String(localized: "Icon-only route") } ?? String(localized: "Unavailable Route") }

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }
}

/// A visible control, not an undiscoverable swipe/context-menu-only action.
struct CapturePresetSettingsPinButton: View {
    let accessibilityID: String
    let name: String
    let isPinned: Bool
    let action: () -> Void

    @Environment(\.editMode) private var editMode

    var body: some View {
        Button(action: action) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.body.weight(.semibold))
                .foregroundStyle(isPinned ? Geist.focus : Geist.faint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(editMode?.wrappedValue.isEditing == true)
        .accessibilityLabel(isPinned
            ? String(localized: "Unpin \(name) from Capture Bar")
            : String(localized: "Pin \(name) to Capture Bar"))
        .accessibilityValue(isPinned ? String(localized: "Pinned") : String(localized: "Not pinned"))
        .accessibilityHint(isPinned
            ? String(localized: "Removes this route from Capture Bar quick actions.")
            : String(localized: "Adds this route to the end of Capture Bar quick actions."))
        .accessibilityIdentifier(accessibilityID)
    }
}

struct CapturePresetSettingsListLabel: View {
    let preset: CapturePreset
    let badge: String?
    /// Signal route card extras. Defaults keep older call sites compact.
    var isDefault = false
    var path: String? = nil
    var steps: [String] = []

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CapturePresetSettingsRouteTile(preset: preset)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(preset.visibleName ?? String(localized: "Icon-only route"))
                            .font(.custom("Geist-SemiBold", size: 17, relativeTo: .body))
                            .foregroundStyle(preset.visibleName == nil ? Geist.muted : Geist.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let badge {
                            SignalBadge(text: "\(badge)")
                        }
                    }
                    Text(path ?? subtitle)
                        .font(Geist.mono(size: 11.5, relativeTo: .caption))
                        .foregroundStyle(Geist.muted)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .truncationMode(.middle)
                    if !preset.isEnabled {
                        Text("Disabled")
                            .font(Geist.caption(.caption))
                            .foregroundStyle(Geist.warning)
                    }
                }
                Spacer(minLength: 0)
            }
            if !steps.isEmpty {
                CapturePresetSettingsStepChips(steps: steps)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        preset.watchOutputMode == .recordingOnly
            ? String(localized: "Recording Only (Watch)")
            : preset.postProcessingMode.displayName
    }
}

/// Letter tile for a preset; icon-only presets keep their chosen icon. The
/// color follows the route's place in the user's order (first indigo, second
/// ink, the rest neutral), matching the Routes board.
struct CapturePresetSettingsRouteTile: View {
    let preset: CapturePreset
    var size: CGFloat = 40

    var body: some View {
        let tone = SignalRouteTileTone.forRoute(id: preset.id)
        if let name = preset.visibleName, let first = name.first {
            SignalRouteTile(letter: String(first), size: size, tone: tone)
        } else {
            CapturePresetIconView(symbolName: preset.symbolName, emoji: preset.emoji)
                .foregroundStyle(SignalRouteTile.letterColor(tone))
                .frame(width: size, height: size)
                .background(
                    SignalRouteTile.fillColor(tone),
                    in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                )
                .accessibilityHidden(true)
        }
    }
}

/// `input → process → deliver` chips under a route card.
struct CapturePresetSettingsStepChips: View {
    let steps: [String]

    var body: some View {
        FlowChipsLayout(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Text(verbatim: "→")
                        .font(Geist.caption(.caption))
                        .foregroundStyle(Geist.Palette.gray600)
                }
                SignalChip(text: step)
            }
        }
    }
}

/// Minimal wrapping layout so long chip rows break instead of truncating.
private struct FlowChipsLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: min(width, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Pass 1: group subviews into rows so each row can be centered vertically.
        var rows: [[(Subviews.Element, CGSize)]] = [[]]
        var x: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((subview, size))
            x += size.width + spacing
        }
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map(\.1.height).max() ?? 0
            var rowX = bounds.minX
            for (subview, size) in row {
                subview.place(
                    at: CGPoint(x: rowX, y: y + (rowHeight - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                rowX += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }
}
