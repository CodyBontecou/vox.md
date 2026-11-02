import SwiftUI
import VoxboardShared

/// Presentation-only identity seam. The parent binding owns persistence, so
/// hosted tests can mount the real editor without routes, Watch, or App Groups.
struct CapturePresetSettingsIdentitySection: View {
    @Binding var preset: CapturePreset

    var body: some View {
        Section {
            TextField("Name (optional)", text: $preset.name)
                .accessibilityIdentifier("capture_preset_name")
            NavigationLink {
                CapturePresetSettingsIconPickerView(preset: $preset)
            } label: {
                HStack(spacing: 12) {
                    Text("Icon")
                    Spacer()
                    CapturePresetIconView(symbolName: preset.symbolName, emoji: preset.emoji)
                        .frame(minWidth: 24)
                    Text(iconDescription)
                        .foregroundStyle(Geist.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityLabel(String(localized: "Icon for \(preset.accessibilityName)"))
            .accessibilityValue(iconDescription)
            .accessibilityIdentifier("capture_preset_icon_picker")
            Toggle("Enabled", isOn: $preset.isEnabled)
                .tint(Geist.accent)
        } header: {
            Text("Identity")
                .textCase(.uppercase)
                .font(Geist.mono(size: 11, relativeTo: .caption))
                .tracking(0.66)
                .foregroundStyle(Geist.muted)
                .accessibilityAddTraits(.isHeader)
        } footer: {
            Text("Leave the name blank to show only the icon in compact Capture controls.")
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
        }
    }

    private var iconDescription: String {
        CapturePresetEmoji.normalized(preset.emoji) == nil
            ? FlowIconPickerView.title(for: preset.symbolName)
            : String(localized: "Emoji")
    }
}

struct CapturePresetSettingsIconPickerView: View {
    @Binding var preset: CapturePreset
    @State private var mode: Mode

    private enum Mode { case symbols, emoji }

    init(preset: Binding<CapturePreset>) {
        self._preset = preset
        // Keep even unrecognized stored emoji losslessly until an explicit edit.
        self._mode = State(initialValue: preset.wrappedValue.emoji == nil ? .symbols : .emoji)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Icon Type", selection: $mode) {
                Text("Symbols").tag(Mode.symbols)
                Text("Emoji").tag(Mode.emoji)
            }
            .pickerStyle(.segmented)
            .padding()
            .accessibilityIdentifier("capture_preset_icon_type")

            switch mode {
            case .symbols:
                FlowIconPickerView(preset: $preset)
            case .emoji:
                CapturePresetEmojiEditorView(preset: $preset)
            }
        }
        .background(Geist.bg.ignoresSafeArea())
        .navigationTitle("Icon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Geist.bg, for: .navigationBar)
        .tint(Geist.accent)
    }
}
