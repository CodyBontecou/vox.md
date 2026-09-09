import SwiftUI

/// Shared copy for the three compact recording controls. Production controls and
/// the visible help sheet use the same text so accessibility and on-screen help
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

/// A compact 44-point affordance. Explanations live in a standard, scrollable
/// sheet so narrow, keyboard-visible, large-text, and RTL layouts do not have to
/// fit verbose copy into the recording control row.
struct CaptureRecordingControlHelp: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            ViewThatFits(in: .horizontal) {
                helpLabel(showsTitle: true)
                helpLabel(showsTitle: false)
            }
            .font(Geist.caption())
            .foregroundStyle(Geist.muted)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Explain recording controls")
        .accessibilityHint("Describes Audio, Import Audio, and Keyboard Listening")
        .accessibilityIdentifier("capture_recording_control_help")
        .sheet(isPresented: $isPresented) {
            CaptureRecordingControlHelpSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func helpLabel(showsTitle: Bool) -> some View {
        HStack(spacing: Geist.Spacing.two) {
            if showsTitle {
                Label("Recording control help", systemImage: "info.circle")
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                Image(systemName: "info.circle")
                    .accessibilityHidden(true)
            }
            Spacer(minLength: Geist.Spacing.two)
            Image(systemName: "chevron.right")
                .font(Geist.caption(.caption2))
                .accessibilityHidden(true)
        }
    }
}

struct CaptureRecordingControlHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
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
            .navigationTitle("Recording Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("capture_recording_control_help_sheet")
    }

    private func helpRow(
        title: String,
        detail: String,
        systemImage: String,
        identifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: Geist.Spacing.three) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(Geist.muted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Geist.Spacing.one) {
                Text(title)
                    .font(Geist.label())
                    .foregroundStyle(Geist.text)
                Text(detail)
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Geist.Spacing.one)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
