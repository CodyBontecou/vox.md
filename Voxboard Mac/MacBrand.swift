import AppKit
import SwiftUI

/// Mac-only brand tokens, mapped onto the shared Signal palette in
/// `GeistTheme.swift`.
///
/// Signal indigo (`#2F3BE8`) is the sole app-authored chromatic accent: Send,
/// the default route tile, selection and the caret. Recording uses Signal red
/// and work that needs the person uses Signal orange, so state stays legible
/// through hue, symbol and copy. Completion uses neutral ink.
///
/// Member names predate Signal (the Mac previously used the app-icon orange)
/// and are kept so call sites keep compiling; `orange*` now means "accent".
enum MacBrand {
    /// Signal accent fill (`#2F3BE8` in both appearances).
    static let orange = Geist.accent
    /// Foreground on `orange` fills. White keeps AA contrast on indigo.
    static let onOrange = Geist.onAccent
    static let ink = Geist.text
    static let muted = Geist.muted
    static let complete = Geist.text
    /// Soft indigo wash for drop targets and selected chips.
    static let subtleOrange = Geist.accentSoft
    static let orangeBorder = Geist.accent.opacity(0.38)

    /// Selected native rows draw AppKit's white label on this fill.
    static let nativeSelectionOrange = Geist.accent

    /// Accent-colored text, lifted in dark mode for contrast on `#0B0B0B`.
    static let orangeText = Geist.accentText
    static let accent = Geist.accent
    static let onAccent = Geist.onAccent
    static let accentText = Geist.accentText
    static let accentSoft = Geist.accentSoft
    /// Control tint (links, pop-up and bordered button labels, checkboxes):
    /// indigo in light, lifted lavender `#9DA4FF` in dark, where the fixed
    /// `#2F3BE8` fill is illegible as text on `#0B0B0B`. Fills that carry
    /// white text (Send, route tile) keep `accent`.
    static let tint = Geist.tint

    /// Signal orange for captures and settings that need the person.
    static let attention = Geist.Palette.amber900
    static let attentionSoft = Geist.Palette.amber100
    static let attentionBorder = Geist.Palette.amber400
    /// Signal "Needs you" status dot (`#E8590C` / `#FF8A4C`).
    static let attentionIndicator = Geist.Palette.amber700
    /// Signal "Delivered" status dot (`#0F7B5F` / `#4CC9A0`).
    static let deliveredIndicator = Geist.Palette.green700
    /// Live recording indicator.
    static let recording = Geist.recording
    static let success = Geist.success

    /// AppKit insertion point and keyboard-hint badges.
    static let appKitOrange = NSColor(
        srgbRed: 47.0 / 255.0,
        green: 59.0 / 255.0,
        blue: 232.0 / 255.0,
        alpha: 1
    )
}

/// Renders the icon compiled into the running app, keeping in-app branding in
/// sync with the Dock/Finder icon without maintaining a duplicate image asset.
struct MacAppIconView: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: size * 0.22,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
            }
            .shadow(
                color: Color.black.opacity(0.16),
                radius: max(1, size * 0.07),
                y: max(1, size * 0.035)
            )
    }
}

// MARK: - Signal Mac components

/// Mono uppercase list/section header used across the Signal Mac layouts
/// (ROUTES, IN FLIGHT, DELIVERED…).
struct MacSignalSectionHeader: View {
    let title: LocalizedStringKey
    var color: Color = Geist.muted

    init(_ title: LocalizedStringKey, color: Color = Geist.muted) {
        self.title = title
        self.color = color
    }

    var body: some View {
        Text(title)
            .textCase(.uppercase)
            .font(Geist.mono(size: 11, relativeTo: .caption))
            .tracking(0.66)
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }
}

/// White card with a hairline border and 14pt corners.
struct MacSignalCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var border: Color = Geist.border

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
    }
}

extension View {
    func macSignalCard(padding: CGFloat = 16, border: Color = Geist.border) -> some View {
        modifier(MacSignalCardModifier(padding: padding, border: border))
    }
}

/// GroupBox rendered as a Signal card with a mono uppercase label.
struct MacSignalGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
                .textCase(.uppercase)
                .font(Geist.mono(size: 11, relativeTo: .caption))
                .tracking(0.66)
                .foregroundStyle(Geist.muted)
            configuration.content
                .frame(maxWidth: .infinity, alignment: .leading)
                .macSignalCard(padding: 14)
        }
    }
}
