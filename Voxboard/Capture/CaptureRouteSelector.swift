import SwiftUI
import VoxboardShared

/// The resting phone header's Route pill: the selected Route's letter tile,
/// name and a chevron that opens the native menu of every enabled Route.
/// While typing, the header swaps this for `CaptureRoutePillsRow`, so Route
/// switching lives in the top bar only (there is no floating side rail).
struct CaptureRouteSelector: View {
    let profiles: [CapturePresetProfile]
    let selectedProfile: CapturePresetProfile
    let canChangeCaptureRoute: Bool
    let selectPreset: (String) -> Bool

    var body: some View {
        Menu {
            presetMenuItems
        } label: {
            selectorLabel
        }
        .accessibilityLabel(Text(verbatim: "Route \(selectedProfile.accessibilityName)"))
        .accessibilityAddTraits(.isSelected)
        .accessibilityHint(String(localized: "Show all Routes"))
        .accessibilityIdentifier("capture_vox_selector")
        .disabled(!canChangeCaptureRoute)
    }

    @ViewBuilder
    private var presetMenuItems: some View {
        ForEach(profiles.filter(\.isEnabled)) { profile in
            Button {
                activatePreset(id: profile.id)
            } label: {
                // UIKit menu image slots cannot render Text, so emoji stays in
                // the title while symbol-only presets use the native image slot.
                if let emoji = CapturePresetEmoji.normalized(profile.emoji) {
                    if let name = profile.visibleName {
                        Text(verbatim: "\(emoji) \(name)")
                    } else {
                        Text(verbatim: emoji)
                    }
                } else {
                    Label(profile.visibleName ?? "", systemImage: profile.symbolName)
                }
            }
            .accessibilityLabel(Text(verbatim: profile.accessibilityName))
            .accessibilityAddTraits(selectedProfile.id == profile.id ? .isSelected : [])
        }
    }

    /// Signal route pill: the route's letter tile (toned by route order),
    /// preset name and a chevron.
    private var selectorLabel: some View {
        HStack(spacing: 8) {
            SignalRouteTile(
                letter: selectedProfile.routeTileLetter,
                size: 24,
                circular: true,
                tone: SignalRouteTileTone.forRoute(
                    at: profiles.filter(\.isEnabled).firstIndex { $0.id == selectedProfile.id }
                )
            )
            if let name = selectedProfile.visibleName {
                Text(name)
                    .font(.custom("Geist-SemiBold", size: 15, relativeTo: .subheadline))
                    .foregroundStyle(Geist.text)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Geist.text)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: 36)
        .background(Geist.card, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(Geist.border, lineWidth: 1))
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }

    /// The exact menu-item action, usable by hosted tests without synthetic
    /// touches. The view model remains the authoritative guard when a
    /// previously rendered menu races a busy state or a deleted preset.
    @discardableResult
    func activatePreset(id: String) -> Bool {
        guard canChangeCaptureRoute,
              profiles.contains(where: { $0.id == id && $0.isEnabled }),
              selectedProfile.id != id else { return false }
        return selectPreset(id)
    }
}
