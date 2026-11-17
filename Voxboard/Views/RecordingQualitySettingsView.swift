import SwiftUI
import VoxboardShared

extension RecordingQuality {
    var displayName: String {
        switch self {
        case .speech: return String(localized: "Speech")
        case .high: return String(localized: "High")
        case .lossless: return String(localized: "Lossless")
        }
    }

    var formatSummary: String {
        switch self {
        case .speech: return String(localized: "16 kHz mono AAC")
        case .high: return String(localized: "48 kHz mono AAC, about 64 kbps")
        case .lossless: return String(localized: "48 kHz mono Apple Lossless (ALAC)")
        }
    }

    var settingsDescription: String {
        switch self {
        case .speech:
            return String(localized: "Smallest files, tuned for transcription. Default.")
        case .high:
            return String(localized: "Clear playback for calls and meetings you keep.")
        case .lossless:
            return String(localized: "Every detail the microphone captures. Large files.")
        }
    }
}

/// Picker for the quality of the audio Vox.md keeps. Transcription always
/// uses a 16 kHz copy, so this changes the saved file, not the transcript.
struct RecordingQualitySettingsView: View {
    var onChange: (RecordingQuality) -> Void = { _ in }

    @State private var selection = RecordingQuality.load(from: AppConstants.sharedDefaults)

    var body: some View {
        Form {
            Section {
                ForEach(RecordingQuality.allCases) { quality in
                    Button {
                        guard selection != quality else { return }
                        selection = quality
                        RecordingQuality.save(quality, to: AppConstants.sharedDefaults)
                        onChange(quality)
                    } label: {
                        row(quality)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("recording_quality_\(quality.rawValue)")
                    .accessibilityAddTraits(selection == quality ? .isSelected : [])
                }
            } footer: {
                Text("Applies to new recordings on iPhone and Apple Watch. Existing recordings are not changed. Transcription always uses a 16 kHz copy, so accuracy is the same at every quality.")
            }
            .listRowBackground(Geist.card)

            if selection != .speech {
                Section {
                    Label {
                        Text("High and Lossless use more Apple Watch battery and take longer to send to iPhone.")
                            .font(Geist.caption())
                            .foregroundStyle(Geist.muted)
                    } icon: {
                        Image(systemName: "applewatch")
                            .foregroundStyle(Geist.muted)
                    }
                    .accessibilityIdentifier("recording_quality_watch_note")
                }
                .listRowBackground(Geist.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Geist.bg.ignoresSafeArea())
        .navigationTitle("Recording Quality")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ quality: RecordingQuality) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(quality.displayName)
                        .font(Geist.label(.body))
                        .foregroundStyle(Geist.text)
                    Text(quality.approximateStoragePerMinuteDescription)
                        .font(Geist.mono(size: 11, relativeTo: .caption))
                        .foregroundStyle(Geist.muted)
                }
                Text(quality.formatSummary)
                    .font(Geist.mono(size: 11, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)
                Text(quality.settingsDescription)
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if selection == quality {
                Image(systemName: "checkmark")
                    .foregroundStyle(Geist.accentText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
