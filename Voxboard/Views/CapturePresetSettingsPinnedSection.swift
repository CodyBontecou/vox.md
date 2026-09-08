import SwiftUI
import VoxboardShared

/// Uses the stored-ID collection directly so disabled and unavailable rows have
/// real move offsets. Native EditButton/onMove provides draggable ordering.
struct CapturePresetSettingsPinnedSection: View {
    let pins: CapturePresetSettingsPins

    var body: some View {
        Section {
            if pins.orderedIDs.isEmpty {
                Text("No pinned presets. Pin a preset below to show it in the Capture Bar.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("capture_preset_pins_empty")
            }
            ForEach(pins.orderedIDs, id: \.self) { id in
                CapturePresetSettingsPinnedRow(id: id, profile: pins.profile(id: id)) {
                    pins.setPinned(false, id: id)
                }
            }
            .onMove { offsets, destination in
                pins.move(fromOffsets: offsets, toOffset: destination)
            }
        } header: {
            Text("Capture Bar")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tap Edit to drag pinned presets into order. Disabled presets keep their place but are hidden until enabled. Pinning does not change your default or keyboard preset.")
                if let message = pins.errorMessage ?? pins.storageMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("capture_preset_pins_error")
                    Button("Reload") { pins.reload() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("capture_preset_pins_reload")
                }
            }
        }
    }
}

private struct CapturePresetSettingsPinnedRow: View {
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

    private var name: String { profile?.displayName ?? String(localized: "Unavailable Preset") }

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

    var body: some View {
        Button(action: action) {
            Text(isPinned ? "Unpin" : "Pin")
                .font(.callout)
                .padding(.horizontal, 8)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isPinned
            ? String(localized: "Unpin \(name) from Capture Bar")
            : String(localized: "Pin \(name) to Capture Bar"))
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
                Text(preset.displayName)
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
