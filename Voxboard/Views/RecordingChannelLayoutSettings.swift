import SwiftUI
import VoxboardShared

// Settings → Recording Quality: the Mono / Stereo / Spatial Audio choice for
// High and Lossless on iPhone (#118, #133). Never synced to Apple Watch.

extension RecordingChannelLayout {
    var displayName: String {
        switch self {
        case .mono: return String(localized: "Mono")
        case .stereo: return String(localized: "Stereo")
        case .spatial: return String(localized: "Spatial Audio")
        }
    }

    /// The layout new recordings at `quality` use on this device, as the
    /// settings screen shows it.
    static func effective(
        quality: RecordingQuality,
        stored: RecordingChannelLayout,
        support: SpatialAudioCaptureSupport
    ) -> RecordingChannelLayout {
        requested(quality: quality, stored: stored, spatialAvailable: support == .supported)
    }
}

extension RecordingQuality {
    /// "≈ 3 MB/min" for this quality in `layout`, in the UI language.
    func localizedStoragePerMinute(layout: RecordingChannelLayout) -> String {
        guard layout == .spatial, supportsStereo else {
            return localizedStoragePerMinute(stereo: layout == .stereo)
        }
        let language = Bundle.main.preferredLocalizations.first
        let locale = language.map(Locale.init(identifier:)) ?? .current
        let megabytes = layout.approximateMegabytesPerMinuteText(quality: self, locale: locale)
        return String(localized: "≈ \(megabytes) MB/min")
    }

    func formatSummary(layout: RecordingChannelLayout) -> String {
        guard layout == .spatial else { return formatSummary(stereo: layout == .stereo) }
        switch self {
        case .speech: return formatSummary(stereo: false)
        case .high: return String(localized: "48 kHz Spatial Audio (APAC) with a stereo AAC track")
        case .lossless: return String(localized: "48 kHz Spatial Audio (APAC) with a stereo Apple Lossless track")
        }
    }

    /// Settings summary row when Spatial Audio is chosen ("High · Spatial
    /// Audio · ≈ 3 MB/min"; "High · Stereo · …" where it falls back to
    /// Stereo); nil for the other choices, which keep the existing summary.
    func spatialSettingsSummary(storedLayout: RecordingChannelLayout) -> String? {
        guard storedLayout == .spatial, supportsStereo else { return nil }
        let layout = RecordingChannelLayout.effective(
            quality: self,
            stored: storedLayout,
            support: SpatialAudioCaptureSupport.current
        )
        let name = String(localized: "\(displayName) · \(layout.displayName)")
        return String(localized: "\(name) · \(localizedStoragePerMinute(layout: layout))")
    }
}

/// Rows of the layout choice, inside the Recording Quality form's section.
struct RecordingChannelLayoutRows: View {
    let quality: RecordingQuality
    @Binding var layout: RecordingChannelLayout
    let support: SpatialAudioCaptureSupport
    let keyboardListeningOn: Bool
    var onChange: () -> Void

    private var effective: RecordingChannelLayout {
        .effective(quality: quality, stored: layout, support: support)
    }

    /// Spatial is hidden where it can't record (not an iPhone, iOS before 26,
    /// a microphone without FOA); the footer says why.
    private var choices: [RecordingChannelLayout] {
        support == .unavailable ? [.mono, .stereo] : RecordingChannelLayout.allCases
    }

    var body: some View {
        ForEach(choices) { choice in
            let enabled = choice != .spatial || support == .supported
            Button {
                guard enabled, effective != choice else { return }
                layout = choice
                RecordingChannelLayout.save(choice, to: AppConstants.sharedDefaults)
                onChange()
            } label: {
                row(choice, enabled: enabled)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityIdentifier("recording_quality_layout_\(choice.rawValue)")
            .accessibilityAddTraits(effective == choice ? .isSelected : [])
        }

        if effective != .mono, keyboardListeningOn {
            Label {
                Group {
                    if effective == .spatial {
                        Text("Keyboard Listening is on, so new recordings are mono. Turn it off to record Spatial Audio.")
                    } else {
                        Text("Keyboard Listening is on, so new recordings are mono. Turn it off to record in stereo.")
                    }
                }
                .font(Geist.caption())
                .foregroundStyle(Geist.text)
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Geist.muted)
            }
            .accessibilityIdentifier("recording_quality_stereo_keyboard_listening_warning")
        }
    }

    private func row(_ choice: RecordingChannelLayout, enabled: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(choice.displayName)
                        .font(Geist.label(.body))
                        .foregroundStyle(enabled ? Geist.text : Geist.muted)
                    Text(quality.localizedStoragePerMinute(layout: choice))
                        .font(Geist.mono(size: 11, relativeTo: .caption))
                        .foregroundStyle(Geist.muted)
                }
                if choice == .spatial, support == .needsMicrophoneAccess {
                    Text("Allow microphone access to use Spatial Audio.")
                        .font(Geist.caption())
                        .foregroundStyle(Geist.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if effective == choice {
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

/// Footer of the layout section.
struct RecordingChannelLayoutFooter: View {
    let support: SpatialAudioCaptureSupport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Records High and Lossless in stereo with the iPhone's built-in microphones, for a more natural sound with music and nature. This works with AirPods connected too. USB microphones and Apple Watch record in mono.")
            if support == .unavailable {
                Text("Spatial Audio needs an iPhone that can record it, on iOS 26 or later.")
                    .accessibilityIdentifier("recording_quality_spatial_unavailable")
            } else {
                Text("Spatial Audio records sound from all around the iPhone and saves an .mp4 file with a stereo track for other players. It uses the built-in microphones; other microphones record in mono.")
                    .accessibilityIdentifier("recording_quality_spatial_note")
            }
            // Keyboard Listening keeps one always-on mono input so dictation
            // transcripts don't change; recordings that reuse it are mono too.
            Text("Keyboard dictation, and recordings made while Keyboard Listening is on, stay mono.")
                .accessibilityIdentifier("recording_quality_stereo_keyboard_note")
        }
    }
}
