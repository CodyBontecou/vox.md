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

    /// "≈ 0.5 MB/min". The number uses the app's UI language, not the device
    /// region, so it reads the same way as the words around it. With Stereo on,
    /// High and Lossless show the two-channel size.
    func localizedStoragePerMinute(stereo: Bool = false) -> String {
        let language = Bundle.main.preferredLocalizations.first
        let locale = language.map(Locale.init(identifier:)) ?? .current
        let megabytes = approximateMegabytesPerMinuteText(
            channelCount: StereoRecordingPreference.requestedChannelCount(quality: self, enabled: stereo),
            locale: locale
        )
        return String(localized: "≈ \(megabytes) MB/min")
    }

    var localizedStoragePerMinute: String { localizedStoragePerMinute() }

    func formatSummary(stereo: Bool = false) -> String {
        let stereo = StereoRecordingPreference.requestsStereo(quality: self, enabled: stereo)
        switch self {
        case .speech: return String(localized: "16 kHz mono AAC")
        case .high:
            return stereo
                ? String(localized: "48 kHz stereo AAC, about 128 kbps")
                : String(localized: "48 kHz mono AAC, about 64 kbps")
        case .lossless:
            return stereo
                ? String(localized: "48 kHz stereo Apple Lossless (ALAC)")
                : String(localized: "48 kHz mono Apple Lossless (ALAC)")
        }
    }

    var formatSummary: String { formatSummary() }

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
    @State private var layout = RecordingChannelLayout.load(from: AppConstants.sharedDefaults)
    @State private var spatialSupport = SpatialAudioCaptureSupport.current
    @State private var natural = NaturalRecordingPreference.load(from: AppConstants.sharedDefaults)
    /// Keyboard Listening keeps the always-on mono input, which new
    /// recordings reuse; warn when that overrides Stereo.
    @State private var keyboardListeningOn = AppConstants.sharedDefaults?
        .bool(forKey: AppConstants.autoListenEnabledKey) ?? false

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

            if selection.supportsStereo {
                Section {
                    RecordingChannelLayoutRows(
                        quality: selection,
                        layout: $layout,
                        support: spatialSupport,
                        keyboardListeningOn: keyboardListeningOn
                    ) { onChange(selection) }
                } footer: {
                    RecordingChannelLayoutFooter(support: spatialSupport)
                }
                .listRowBackground(Geist.card)
            }

            if selection.recordsSeparateKeptAudio {
                Section {
                    // Stereo and Spatial Audio win over Natural sound: the
                    // toggle shows off and is disabled, and the stored choice
                    // comes back when Mono is chosen again.
                    Toggle(isOn: Binding(
                        get: { natural && naturalApplies },
                        set: { enabled in
                            guard natural != enabled else { return }
                            natural = enabled
                            NaturalRecordingPreference.save(enabled, to: AppConstants.sharedDefaults)
                            onChange(selection)
                        }
                    )) {
                        Text("Natural sound")
                            .font(Geist.label(.body))
                            .foregroundStyle(Geist.text)
                    }
                    .tint(Geist.accent)
                    .disabled(!naturalApplies)
                    .accessibilityIdentifier("recording_quality_natural")

                    if !naturalApplies {
                        Text("Natural sound records in mono. Stereo and Spatial Audio keep the iPhone's standard microphone processing.")
                            .font(Geist.caption())
                            .foregroundStyle(Geist.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("recording_quality_natural_mono_only")
                    }

                    if natural, naturalApplies, keyboardListeningOn {
                        Label {
                            Text("Keyboard Listening is on, so new recordings use the standard microphone settings. Turn it off to use Natural sound.")
                                .font(Geist.caption())
                                .foregroundStyle(Geist.text)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(Geist.muted)
                        }
                        .accessibilityIdentifier("recording_quality_natural_keyboard_listening_warning")
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Records High and Lossless with less of the iPhone's own input processing, for a more natural sound with music, nature and rooms. Quiet speech can come out quieter, and transcripts may change slightly.")
                        // High-quality Bluetooth is automatic for High and
                        // Lossless (RecordingAudioSessionConfiguration).
                        Text("On iOS 26, AirPods that support it record High and Lossless in full Bluetooth quality instead of call quality.")
                            .accessibilityIdentifier("recording_quality_airpods_note")
                    }
                }
                .listRowBackground(Geist.card)
            }

            if selection != .speech {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("High and Lossless use more Apple Watch battery and take longer to send to iPhone.")
                            if effectiveLayout != .mono {
                                // The sizes above are stereo or spatial; the Watch
                                // has one microphone and keeps recording mono.
                                Text("Apple Watch records in mono: \(selection.localizedStoragePerMinute(stereo: false))")
                            }
                        }
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
        .onAppear {
            keyboardListeningOn = AppConstants.sharedDefaults?
                .bool(forKey: AppConstants.autoListenEnabledKey) ?? false
            spatialSupport = SpatialAudioCaptureSupport.current
        }
        .navigationTitle("Recording Quality")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var effectiveLayout: RecordingChannelLayout { layout(for: selection) }

    /// Natural sound only applies to Mono (see `NaturalRecordingPreference`).
    private var naturalApplies: Bool { effectiveLayout == .mono }

    private func layout(for quality: RecordingQuality) -> RecordingChannelLayout {
        .effective(quality: quality, stored: layout, support: spatialSupport)
    }

    private func row(_ quality: RecordingQuality) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(quality.displayName)
                        .font(Geist.label(.body))
                        .foregroundStyle(Geist.text)
                    Text(quality.localizedStoragePerMinute(layout: layout(for: quality)))
                        .font(Geist.mono(size: 11, relativeTo: .caption))
                        .foregroundStyle(Geist.muted)
                }
                Text(quality.formatSummary(layout: layout(for: quality)))
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
