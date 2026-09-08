import SwiftUI
import VoxboardShared

/// Presentation only: order/availability come from resolved shared pins; the
/// callback must revalidate live route ownership and preset availability.
/// This row never owns, focuses, or replaces the Markdown editor.
struct CapturePresetQuickAccessRow: View {
    let profiles: [CapturePresetProfile]
    let selectedID: String?
    let canChangeCaptureRoute: Bool
    let selectPreset: (String) -> Bool

    var body: some View {
        if !profiles.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(profiles) { profile in
                        CapturePresetQuickAccessButton(profile: profile, isSelected: selectedID == profile.id) {
                            activatePreset(id: profile.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.never)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(!canChangeCaptureRoute)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("capture_preset_quick_access")
        }
    }

    /// The exact Button action, also usable by hosted tests without microphone
    /// or synthetic touches. The coordinator/VM remains the authoritative guard
    /// when a previously rendered row races a busy state or a deleted preset.
    @discardableResult
    func activatePreset(id: String) -> Bool {
        guard canChangeCaptureRoute,
              profiles.contains(where: { $0.id == id && $0.isEnabled }),
              selectedID != id else { return false }
        return selectPreset(id)
    }
}

/// Nominal button shared by the row and mounted hit-target regression tests.
struct CapturePresetQuickAccessButton: View {
    let profile: CapturePresetProfile
    let isSelected: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var iconSize = 22.0
    @ScaledMetric(relativeTo: .body) private var buttonSide = 52.0

    var body: some View {
        Button(action: action) {
            CapturePresetIconView(symbolName: profile.symbolName, emoji: profile.emoji)
                .font(.system(size: iconSize, weight: .medium))
                .frame(width: max(44, buttonSide), height: max(44, buttonSide))
                .foregroundStyle(isSelected ? Geist.Palette.blue700 : Geist.text)
                .background(isSelected ? Geist.Palette.blue700.opacity(0.12) : Geist.Palette.background200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? Geist.Palette.blue700 : .clear, lineWidth: 2)
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Geist.Palette.blue700)
                            .padding(3)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: profile.displayName))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected
            ? String(localized: "Already selected. One-off routing is kept.")
            : String(localized: "Use this preset for the current draft. Text and attachments are kept."))
        .accessibilityIdentifier("capture_preset_pin_\(profile.id)")
    }

}
