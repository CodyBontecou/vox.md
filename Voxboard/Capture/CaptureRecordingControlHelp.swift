import SwiftUI

/// Shared copy for the three compact recording controls. Production controls and
/// the visible disclosure use the same text so accessibility and on-screen help
/// cannot drift into describing different behaviors.
enum CaptureRecordingControlSemantics {
    static var audioHelp: String {
        String(localized: "Keep the new recording attached when adding it to the current draft. With Audio off, the transcript is still added when available.")
    }

    static var importAudioHelp: String {
        String(localized: "Choose an existing audio or video file. Vox.md processes it and adds the transcript or result to the current Capture flow.")
    }

    static var keyboardListeningHelp: String {
        String(localized: "Start or stop the persistent listening session used by the Vox.md keyboard. This is not another attachment mode.")
    }

    static func keyboardListeningLabel(isListening: Bool) -> String {
        isListening
            ? String(localized: "Stop keyboard listening")
            : String(localized: "Start keyboard listening")
    }

    static func keyboardListeningActionHint(isListening: Bool) -> String {
        isListening
            ? String(localized: "Stops the persistent listening session used by the Vox.md keyboard. This does not change Capture attachments.")
            : String(localized: "Starts the persistent listening session used by the Vox.md keyboard. This does not attach audio to the Capture.")
    }
}

/// A compact, collapsed-by-default explanation that expands vertically instead
/// of forcing verbose labels into the recording control row.
struct CaptureRecordingControlHelp: View {
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: Geist.Spacing.three) {
                helpRow(
                    title: String(localized: "Audio"),
                    detail: CaptureRecordingControlSemantics.audioHelp,
                    systemImage: "paperclip",
                    identifier: "capture_recording_help_audio"
                )
                helpRow(
                    title: String(localized: "Import Audio"),
                    detail: CaptureRecordingControlSemantics.importAudioHelp,
                    systemImage: "waveform.badge.plus",
                    identifier: "capture_recording_help_import_audio"
                )
                helpRow(
                    title: String(localized: "Keyboard Listening"),
                    detail: CaptureRecordingControlSemantics.keyboardListeningHelp,
                    systemImage: "headphones.circle",
                    identifier: "capture_recording_help_keyboard_listening"
                )
            }
            .padding(.top, Geist.Spacing.two)
        } label: {
            Label("Recording control help", systemImage: "info.circle")
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
        }
        .accessibilityIdentifier("capture_recording_control_help")
    }

    private func helpRow(
        title: String,
        detail: String,
        systemImage: String,
        identifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: Geist.Spacing.two) {
            Image(systemName: systemImage)
                .frame(width: 20)
                .foregroundStyle(Geist.muted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Geist.label())
                    .foregroundStyle(Geist.text)
                Text(detail)
                    .font(Geist.caption(.caption2))
                    .foregroundStyle(Geist.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
