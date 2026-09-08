import SwiftUI
import VoxboardShared

/// Uncommitted native text input. Validation never rewrites the text field or
/// the preset while a grapheme (or a pasted string) is still being composed.
struct CapturePresetEmojiEditorInput {
    var text: String

    var normalizedEmoji: String? { CapturePresetEmoji.normalized(text) }
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var validationMessage: String? {
        guard normalizedEmoji == nil else { return nil }
        return isEmpty
            ? String(localized: "Enter one emoji to preview it, or choose a symbol.")
            : String(localized: "Enter a single emoji, not text or multiple emoji. Your current icon has not changed.")
    }

    /// One binding write at the existing preset-save boundary, only on Apply.
    func applying(to preset: CapturePreset) -> CapturePreset? {
        guard let normalizedEmoji else { return nil }
        var updated = preset
        updated.emoji = normalizedEmoji
        return updated
    }

    /// Choosing a symbol clears emoji atomically and retains all other fields.
    static func selectingSymbol(_ symbolName: String, for preset: CapturePreset) -> CapturePreset {
        var updated = preset
        updated.symbolName = symbolName
        updated.emoji = nil
        return updated
    }
}

/// A native emoji-capable TextField, with explicit preview/apply instead of
/// truncating an in-progress or pasted multi-grapheme value in an onChange.
struct CapturePresetEmojiEditorView: View {
    @Binding var preset: CapturePreset
    @State private var input: CapturePresetEmojiEditorInput
    @Environment(\.dismiss) private var dismiss

    init(preset: Binding<CapturePreset>) {
        self._preset = preset
        self._input = State(initialValue: CapturePresetEmojiEditorInput(text: preset.wrappedValue.emoji ?? ""))
    }

    var body: some View {
        Form {
            Section {
                TextField("Emoji", text: $input.text)
                    .keyboardType(.default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .accessibilityLabel(String(localized: "Emoji for \(preset.displayName)"))
                    .accessibilityHint(input.validationMessage ?? String(localized: "Apply to save this icon."))
                    .accessibilityIdentifier("capture_preset_emoji_input")
                    .onSubmit { apply() }

                if let message = input.validationMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(input.isEmpty ? Color.secondary : .red)
                        .accessibilityIdentifier("capture_preset_emoji_validation")
                }
            } header: {
                Text("Emoji")
            } footer: {
                Text("Use the emoji keyboard or paste one emoji. Flags, skin tones, and family emoji are supported.")
            }

            Section {
                HStack(spacing: 16) {
                    CapturePresetIconView(
                        symbolName: preset.symbolName,
                        emoji: input.normalizedEmoji ?? preset.emoji
                    )
                    .font(.largeTitle)
                    .frame(minWidth: 44, minHeight: 44)
                    Text(preset.displayName)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(preset.displayName)
                .accessibilityValue(input.normalizedEmoji == nil ? Text("Current Icon") : Text("Preview"))
                .accessibilityIdentifier("capture_preset_emoji_preview")

                Button("Apply Emoji") { apply() }
                    .frame(minHeight: 44)
                    .disabled(input.normalizedEmoji == nil)
                    .accessibilityLabel(String(localized: "Apply emoji for \(preset.displayName)"))
                    .accessibilityIdentifier("capture_preset_emoji_apply")
            } header: {
                Text(input.normalizedEmoji == nil ? "Current Icon" : "Preview")
            }

            Section {
                Button("Use Symbol Instead") {
                    preset = CapturePresetEmojiEditorInput.selectingSymbol(preset.symbolName, for: preset)
                    dismiss()
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("capture_preset_emoji_use_symbol")
            } footer: {
                Text("Your symbol is kept as a fallback for surfaces that cannot display emoji.")
            }
        }
    }

    private func apply() {
        guard let updated = input.applying(to: preset) else { return }
        preset = updated
        dismiss()
    }
}
