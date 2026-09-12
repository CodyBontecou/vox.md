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
                    .frame(minWidth: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .foregroundStyle(profile?.visibleName == nil ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if profile == nil {
                        Text("Unavailable — unpin or reload")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if profile?.isEnabled == false {
                        Text("Hidden until enabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    private var name: String { profile.map { $0.visibleName ?? String(localized: "Icon-only preset") } ?? String(localized: "Unavailable Preset") }

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
                .foregroundStyle(isPinned ? Color.accentColor : .secondary)
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
            ? String(localized: "Removes this preset from Capture Bar quick actions.")
            : String(localized: "Adds this preset to the end of Capture Bar quick actions."))
        .accessibilityIdentifier(accessibilityID)
    }
}

struct CapturePresetSettingsListLabel: View {
    let preset: CapturePreset
    let badge: String?

    var body: some View {
        HStack(spacing: 12) {
            CapturePresetIconView(symbolName: preset.symbolName, emoji: preset.emoji)
                .frame(minWidth: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.visibleName ?? String(localized: "Icon-only preset"))
                    .foregroundStyle(preset.visibleName == nil ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(preset.watchOutputMode == .recordingOnly
                    ? String(localized: "Recording Only (Watch)")
                    : preset.postProcessingMode.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !preset.isEnabled {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let badge {
                    Text(badge)
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
