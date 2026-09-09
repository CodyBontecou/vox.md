import SwiftUI
import VoxboardShared

/// Presentation only: order/availability come from resolved shared pins; the
/// callback must revalidate live route ownership and preset availability.
/// The highest-priority pin stays nearest the controls and additional pins rise
/// up its configured physical edge. The coordinator places this container without
/// overriding semantic direction; this rail never owns, focuses, or replaces the editor.
struct CapturePresetQuickAccessRail: View {
    let profiles: [CapturePresetProfile]
    let selectedID: String?
    let isExpanded: Bool
    let canChangeCaptureRoute: Bool
    let selectPreset: (String) -> Bool

    /// The selected preset already lives in the disclosure control directly
    /// below this rail. Showing it again made the expanded state look duplicated.
    var alternateProfiles: [CapturePresetProfile] {
        profiles.filter { $0.id != selectedID }
    }

    var body: some View {
        if isExpanded && !alternateProfiles.isEmpty {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(alternateProfiles.reversed()) { profile in
                                CapturePresetQuickAccessButton(
                                    profile: profile,
                                    isSelected: false
                                ) {
                                    activatePreset(id: profile.id)
                                }
                                // Stored order reads from the controls upward,
                                // matching its old leading-to-trailing priority.
                                .accessibilitySortPriority(accessibilityPriority(for: profile))
                            }
                        }
                        .padding(.vertical, Geist.Spacing.one)
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.never)
                    .scrollBounceBehavior(.basedOnSize)
                    // A short rail should claim only its visible controls, not
                    // an invisible full-height strip over the text editor.
                    .frame(height: viewportHeight(available: proxy.size.height))

                    Spacer().frame(height: Geist.Spacing.one)
                }
            }
            .frame(width: CapturePresetQuickAccessButton.hitTargetSide)
            .disabled(!canChangeCaptureRoute)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("capture_preset_quick_access")
            .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            .zIndex(1)
        }
    }

    private func accessibilityPriority(for profile: CapturePresetProfile) -> Double {
        guard let index = alternateProfiles.firstIndex(where: { $0.id == profile.id }) else { return 0 }
        return Double(alternateProfiles.count - index)
    }

    private func viewportHeight(available: CGFloat) -> CGFloat {
        let bottomGap = Geist.Spacing.one
        let availableHeight = max(0, available - bottomGap)
        let contentHeight = CGFloat(alternateProfiles.count)
            * CapturePresetQuickAccessButton.hitTargetSide
            + (2 * Geist.Spacing.one)
        return min(availableHeight, contentHeight)
    }

    /// The exact Button action, also usable by hosted tests without microphone
    /// or synthetic touches. The coordinator/VM remains the authoritative guard
    /// when a previously rendered rail races a busy state or a deleted preset.
    @discardableResult
    func activatePreset(id: String) -> Bool {
        guard isExpanded,
              canChangeCaptureRoute,
              profiles.contains(where: { $0.id == id && $0.isEnabled }),
              selectedID != id else { return false }
        return selectPreset(id)
    }
}

/// The existing all-presets selector doubles as the compact/expanded rail
/// control. A tap toggles pinned presets; a touch-and-hold retains access to the
/// complete native preset menu. With no usable pins it remains a normal menu.
struct CapturePresetQuickAccessSelector: View {
    let profiles: [CapturePresetProfile]
    let selectedProfile: CapturePresetProfile
    let hasQuickAccessProfiles: Bool
    let isRailExpanded: Bool
    let canChangeCaptureRoute: Bool
    let toggleRail: () -> Void
    let selectPreset: (String) -> Bool

    var body: some View {
        Group {
            if hasQuickAccessProfiles {
                Menu {
                    presetMenuItems
                } label: {
                    selectorLabel
                } primaryAction: {
                    toggleRailIfAvailable()
                }
            } else {
                Menu {
                    presetMenuItems
                } label: {
                    selectorLabel
                }
            }
        }
        .accessibilityLabel(Text(verbatim: "Capture Preset \(selectedProfile.displayName)"))
        .accessibilityAddTraits(accessibilitySelectionTraits)
        .accessibilityHint(accessibilityHint)
        .accessibilityValue(accessibilityValue)
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
                    Text(verbatim: "\(emoji) \(profile.displayName)")
                } else {
                    Label(profile.displayName, systemImage: profile.symbolName)
                }
            }
            .accessibilityLabel(Text(verbatim: profile.displayName))
            .accessibilityAddTraits(selectedProfile.id == profile.id ? .isSelected : [])
        }
    }

    private var selectorLabel: some View {
        HStack(spacing: 6) {
            CapturePresetIconView(
                symbolName: selectedProfile.symbolName,
                emoji: selectedProfile.emoji
            )
            Text(selectedProfile.displayName)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
        }
        .frame(
            minWidth: CapturePresetQuickAccessButton.hitTargetSide,
            minHeight: CapturePresetQuickAccessButton.hitTargetSide
        )
        .contentShape(Rectangle())
        .foregroundStyle(isRailExpanded && hasQuickAccessProfiles ? Geist.Palette.blue700 : Geist.muted)
    }

    var accessibilitySelectionTraits: AccessibilityTraits { .isSelected }

    var accessibilityHint: String {
        guard hasQuickAccessProfiles else {
            return String(localized: "Show all Capture Presets")
        }
        return isRailExpanded
            ? String(localized: "Collapse pinned Capture Presets. Use the Show Menu action for all Capture Presets.")
            : String(localized: "Expand pinned Capture Presets. Use the Show Menu action for all Capture Presets.")
    }

    var accessibilityValue: String {
        guard hasQuickAccessProfiles else { return "" }
        return isRailExpanded ? String(localized: "Expanded") : String(localized: "Collapsed")
    }

    /// The Menu's primary action seam. Selection remains independent and the
    /// fallback no-pin Menu keeps its ordinary tap behavior.
    @discardableResult
    func toggleRailIfAvailable() -> Bool {
        guard hasQuickAccessProfiles, canChangeCaptureRoute else { return false }
        toggleRail()
        return true
    }

    @discardableResult
    func activatePreset(id: String) -> Bool {
        guard canChangeCaptureRoute,
              profiles.contains(where: { $0.id == id && $0.isEnabled }),
              selectedProfile.id != id else { return false }
        return selectPreset(id)
    }
}

/// Small icon-only control with an independent 44-point interaction target.
struct CapturePresetQuickAccessButton: View {
    static let hitTargetSide: CGFloat = 44
    static let iconSize: CGFloat = 14

    let profile: CapturePresetProfile
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CapturePresetIconView(symbolName: profile.symbolName, emoji: profile.emoji)
                .font(.system(size: Self.iconSize, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Geist.Palette.blue700 : Geist.muted)
                .opacity(isSelected ? 1 : 0.68)
                .frame(width: Self.hitTargetSide, height: Self.hitTargetSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: profile.displayName))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier("capture_preset_pin_\(profile.id)")
    }

    var accessibilityHint: String {
        isSelected
            ? String(localized: "Already selected. One-off routing is kept.")
            : String(localized: "Use this preset for the current draft. Text and attachments stay in place; one-off route overrides reset.")
    }
}
