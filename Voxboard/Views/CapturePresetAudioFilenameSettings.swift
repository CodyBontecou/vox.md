import SwiftUI
import VoxboardShared

/// Binding-only fields for the normal Capture Preset audio filename. The
/// enclosing editor owns persistence; this view only presents and edits the
/// raw template while the shared renderer owns filename safety.
struct CapturePresetAudioFilenameSettings: View {
    @Binding var preset: CapturePreset

    static let fieldLabel = String(localized: "Audio Filename Template")
    static let fieldPlaceholder = String(localized: "Automatic filename")
    static let fieldAccessibilityIdentifier = "capture_preset_audio_filename_template"
    static let helpAccessibilityIdentifier = "capture_preset_audio_filename_help"
    static let previewAccessibilityIdentifier = "capture_preset_audio_filename_preview"
    static let tokensHelp = String(
        localized: "Tokens: {timestamp}, {date}, {time}, {YR} (2-digit year), {id}, {id8}, {preset}, {original}."
    )
    static let behaviorHelp = String(
        localized: "Leave blank to keep the existing automatic name. A typed extension is ignored; Vox.md uses the actual encoded or copied audio extension. Unsafe characters and path-like input are sanitized into one filename."
    )
    static let fieldAccessibilityHint = String(
        localized: "Sets this preset’s saved voice-audio filename. Leave blank for automatic naming. Unsafe path input is sanitized, and the actual audio extension replaces any typed extension."
    )

    var body: some View {
        if preset.audioSaveMode != .off {
            VStack(alignment: .leading, spacing: 6) {
                Text(Self.fieldLabel)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                TextField(Self.fieldPlaceholder, text: $preset.audioFilenameTemplate)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .accessibilityLabel(Self.fieldLabel)
                    .accessibilityHint(Self.fieldAccessibilityHint)
                    .accessibilityIdentifier(Self.fieldAccessibilityIdentifier)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.tokensHelp)
                Text(Self.behaviorHelp)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(Self.helpAccessibilityIdentifier)

            if let preview = Self.previewFilename(for: preset) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Example")
                        .font(.caption.weight(.semibold))
                    Text(preview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Example Audio Filename")
                .accessibilityValue(preview)
                .accessibilityIdentifier(Self.previewAccessibilityIdentifier)
            }
        }
    }

    /// A deterministic illustrative context keeps the settings preview stable;
    /// delivery supplies the real transcript identity, date, preset, and source.
    static func previewFilename(for preset: CapturePreset) -> String? {
        CapturePresetAudioFilename.preferredFilename(
            template: preset.audioFilenameTemplate,
            context: CapturePresetAudioFilenameContext(
                identifier: "01234567-89AB-CDEF-0123-456789ABCDEF",
                createdAt: Date(timeIntervalSince1970: 1_704_164_645),
                presetName: preset.visibleName ?? "",
                originalFilename: "Original Recording.wav",
                timeZone: TimeZone(secondsFromGMT: 0) ?? .current
            ),
            sourceExtension: "m4a"
        )
    }
}
