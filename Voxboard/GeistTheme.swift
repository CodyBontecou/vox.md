import SwiftUI
import Combine
import CoreText
import VoxboardShared

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Geist design system

/// The app's UI tokens follow the "Signal" redesign: a warm paper ground,
/// near-black ink, white cards, one indigo accent and a recording red. Dark
/// mode inverts to a near-black ground with raised charcoal cards. Names keep
/// the original Geist scale so existing call sites pick up the new values.
enum Geist {
    enum Spacing {
        static let one: CGFloat = 4
        static let two: CGFloat = 8
        static let three: CGFloat = 12
        static let four: CGFloat = 16
        static let six: CGFloat = 24
        static let eight: CGFloat = 32
        static let ten: CGFloat = 40
        static let sixteen: CGFloat = 64
        static let twentyFour: CGFloat = 96
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 14
        static let large: CGFloat = 18
        static let full: CGFloat = 9_999
    }

    enum ControlHeight {
        static let small: CGFloat = 32
        static let medium: CGFloat = 44
        static let large: CGFloat = 52
        /// The primary Speak / Record control.
        static let hero: CGFloat = 64
    }

    enum Palette {
        // Page ground. Shared with the keyboard's opaque backdrop for a seamless transition.
        static let background100 = adaptive("#f2f2ee", "#0b0b0b")
        static let background200 = adaptive("#f2f2ee", "#0b0b0b")
        /// Raised cards, pills and secondary controls.
        static let card = adaptive("#ffffff", "#161616")

        static let gray100 = adaptive("#f7f7f4", "#161616")
        static let gray200 = adaptive("#ecece6", "#1c1c1c")
        static let gray300 = adaptive("#e3e3dc", "#222220")
        static let gray400 = adaptive("#deded8", "#2a2a28")
        static let gray500 = adaptive("#c9c9c3", "#3a3a38")
        static let gray600 = adaptive("#a3a39e", "#6a6a66")
        static let gray700 = adaptive("#8a8a85", "#8a8a85")
        static let gray800 = adaptive("#6b6b66", "#9a9a95")
        static let gray900 = adaptive("#5e5e5a", "#9a9a95")
        static let gray1000 = adaptive("#121212", "#f4f4f1")

        static let grayAlpha100 = adaptive("#1212120a", "#f4f4f10f")
        static let grayAlpha200 = adaptive("#12121212", "#f4f4f114")
        static let grayAlpha300 = adaptive("#1212121a", "#f4f4f11f")
        static let grayAlpha400 = adaptive("#1212121f", "#f4f4f11f")
        static let grayAlpha500 = adaptive("#12121236", "#f4f4f13d")
        static let grayAlpha600 = adaptive("#1212123d", "#f4f4f170")
        static let grayAlpha700 = adaptive("#12121270", "#f4f4f18a")
        static let grayAlpha800 = adaptive("#12121282", "#f4f4f178")
        static let grayAlpha900 = adaptive("#121212b3", "#f4f4f19c")
        static let grayAlpha1000 = adaptive("#121212e8", "#f4f4f1eb")

        // Indigo accent. `blue700` is the tint; `Geist.accent` is the fixed fill.
        static let blue100 = adaptive("#f0f0fd", "#12142e")
        static let blue200 = adaptive("#e6e6fc", "#1b1e4a")
        static let blue300 = adaptive("#dadafb", "#22265c")
        static let blue400 = adaptive("#c4c8ff", "#2c3170")
        static let blue500 = adaptive("#9da4ff", "#3a4090")
        static let blue600 = adaptive("#6e78ff", "#2f3be8")
        static let blue700 = adaptive("#2f3be8", "#6e78ff")
        static let blue800 = adaptive("#1e27b0", "#5a64f0")
        static let blue900 = adaptive("#2f3be8", "#9da4ff")
        static let blue1000 = adaptive("#10165e", "#e6e6fc")

        // Recording red.
        static let red100 = adaptive("#fdeeee", "#2a1112")
        static let red200 = adaptive("#fce6e6", "#351416")
        static let red300 = adaptive("#fadada", "#43181a")
        static let red400 = adaptive("#f6c9c9", "#521c1f")
        static let red500 = adaptive("#f2a6a7", "#6b2427")
        static let red600 = adaptive("#f0474a", "#f0474a")
        static let red700 = adaptive("#f0474a", "#f0474a")
        static let red800 = adaptive("#d93235", "#e03a3d")
        static let red900 = adaptive("#c42a2d", "#ff7a7c")
        static let red1000 = adaptive("#4a0e0f", "#fde6e6")

        // "Needs you" orange.
        static let amber100 = adaptive("#fdf0e8", "#2a1508")
        static let amber400 = adaptive("#f1c9b4", "#6b3a1f")
        static let amber700 = adaptive("#e8590c", "#ff8a4c")
        static let amber900 = adaptive("#c2410c", "#ff8a4c")
        static let amber1000 = adaptive("#5a1e05", "#fde8dc")

        // Delivered green.
        static let green100 = adaptive("#e7f4ef", "#0d251e")
        static let green700 = adaptive("#0f7b5f", "#4cc9a0")
        static let green900 = adaptive("#0f7b5f", "#4cc9a0")
        static let green1000 = adaptive("#06362a", "#d7f5ea")
    }

    // Semantic roles.
    static let bg = Palette.background100
    static let surface = Palette.card
    static let surface2 = Palette.background200
    static let card = Palette.card
    /// Inset wells, segmented-control tracks and neutral chips.
    static let well = Palette.gray300
    static let border = Palette.gray400
    static let borderHi = Palette.gray500
    static let text = Palette.gray1000
    static let muted = Palette.gray900
    static let faint = Palette.gray700
    static let error = Palette.red900
    static let focus = Palette.blue700
    static let success = Palette.green900
    static let warning = Palette.amber700
    /// Fixed indigo fill for Send and the default route tile in both modes.
    static let accent = adaptive("#2f3be8", "#2f3be8")
    static let onAccent = adaptive("#ffffff", "#ffffff")
    /// Soft indigo wash behind `[[links]]` and the DEFAULT badge.
    /// App-wide `.tint` (matches the AccentColor asset): indigo in light,
    /// lifted lavender on the near-black dark ground.
    static let tint = adaptive("#2f3be8", "#9da4ff")
    static let accentSoft = Palette.blue200
    static let accentText = Palette.blue900
    static let recording = Palette.red700

    // MARK: Typography tokens

    static func display(_ size: CGFloat) -> Font {
        .custom("Geist-SemiBold", fixedSize: size)
    }

    static func heading(_ style: Font.TextStyle = .title3) -> Font {
        .custom("Geist-SemiBold", size: headingSize(style), relativeTo: style)
    }

    static func label(_ style: Font.TextStyle = .callout) -> Font {
        .custom("Geist-Medium", size: labelSize(style), relativeTo: style)
    }

    static func body(_ style: Font.TextStyle = .body) -> Font {
        .custom("Geist-Regular", size: bodySize(style), relativeTo: style)
    }

    static func caption(_ style: Font.TextStyle = .footnote) -> Font {
        .custom("Geist-Regular", size: captionSize(style), relativeTo: style)
    }

    static func mono(_ style: Font.TextStyle = .footnote, medium: Bool = false) -> Font {
        .custom(medium ? "GeistMono-Medium" : "GeistMono-Regular", size: captionSize(style), relativeTo: style)
    }

    static func mono(size: CGFloat, relativeTo style: Font.TextStyle = .body, medium: Bool = false) -> Font {
        .custom(medium ? "GeistMono-Medium" : "GeistMono-Regular", size: size, relativeTo: style)
    }

    private static func headingSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 32
        case .title: return 24
        case .title2: return 20
        case .title3: return 20
        case .headline: return 16
        default: return 14
        }
    }

    private static func labelSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .title3: return 20
        case .headline: return 16
        case .body: return 16
        case .callout, .subheadline: return 14
        case .footnote: return 13
        default: return 12
        }
    }

    private static func bodySize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .title2: return 20
        case .title3: return 18
        case .body: return 16
        case .callout, .subheadline: return 14
        default: return 13
        }
    }

    private static func captionSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .headline, .body: return 16
        case .callout, .subheadline: return 14
        case .footnote: return 13
        default: return 12
        }
    }

    /// iOS registers `UIAppFonts` automatically. The macOS target uses the
    /// same bundled files and registers them for this process at launch.
    static func registerBundledFonts() {
#if os(macOS)
        [
            "Geist-Regular",
            "Geist-Medium",
            "Geist-SemiBold",
            "GeistMono-Regular",
            "GeistMono-Medium",
        ].forEach { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { return }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
#endif
    }
}

// MARK: - Adaptive color implementation

private func adaptive(_ light: String, _ dark: String) -> Color {
#if canImport(UIKit)
    Color(uiColor: UIColor { traits in
        platformColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
    })
#elseif canImport(AppKit)
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return platformColor(hex: isDark ? dark : light)
    })
#else
    Color.primary
#endif
}

#if canImport(UIKit)
private func platformColor(hex: String) -> UIColor {
    let rgba = rgbaComponents(hex)
    return UIColor(red: rgba.0, green: rgba.1, blue: rgba.2, alpha: rgba.3)
}
#elseif canImport(AppKit)
private func platformColor(hex: String) -> NSColor {
    let rgba = rgbaComponents(hex)
    return NSColor(srgbRed: rgba.0, green: rgba.1, blue: rgba.2, alpha: rgba.3)
}
#endif

private func rgbaComponents(_ hex: String) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
    let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var raw: UInt64 = 0
    Scanner(string: value).scanHexInt64(&raw)
    if value.count == 8 {
        return (
            CGFloat((raw >> 24) & 0xff) / 255,
            CGFloat((raw >> 16) & 0xff) / 255,
            CGFloat((raw >> 8) & 0xff) / 255,
            CGFloat(raw & 0xff) / 255
        )
    }
    return (
        CGFloat((raw >> 16) & 0xff) / 255,
        CGFloat((raw >> 8) & 0xff) / 255,
        CGFloat(raw & 0xff) / 255,
        1
    )
}

// MARK: - Components

struct GeistButtonStyle: ButtonStyle {
    enum Variant { case primary, accent, secondary, tertiary, destructive }
    enum Size { case small, medium, large }

    let variant: Variant
    var size: Size = .large
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size == .large ? Geist.label(.body) : Geist.label())
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(minHeight: height)
            .padding(.horizontal, horizontalPadding)
            .background(backgroundColor(configuration.isPressed))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(borderColor(configuration.isPressed), lineWidth: borderWidth)
            )
            .clipShape(Capsule(style: .continuous))
            .overlay {
                if isFocused {
                    Capsule(style: .continuous)
                        .stroke(Geist.Palette.background100, lineWidth: 2)
                        .padding(-2)
                    Capsule(style: .continuous)
                        .stroke(Geist.focus, lineWidth: 2)
                        .padding(-4)
                }
            }
            .contentShape(Capsule(style: .continuous))
            .opacity(isEnabled ? 1 : 0.72)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }

    private var height: CGFloat {
        switch size {
        case .small: return Geist.ControlHeight.small
        case .medium: return Geist.ControlHeight.medium
        case .large: return Geist.ControlHeight.large
        }
    }

    private var horizontalPadding: CGFloat { size == .small ? 10 : (size == .large ? 18 : 14) }

    private var foregroundColor: Color {
        guard isEnabled else { return Geist.Palette.gray700 }
        switch variant {
        case .primary: return Geist.Palette.background100
        case .accent: return Geist.onAccent
        case .secondary, .tertiary: return Geist.Palette.gray1000
        case .destructive: return .white
        }
    }

    private func backgroundColor(_ pressed: Bool) -> Color {
        guard isEnabled else { return Geist.Palette.gray100 }
        switch variant {
        case .primary: return pressed ? Geist.Palette.gray900 : Geist.Palette.gray1000
        case .accent: return pressed ? Geist.Palette.blue800 : Geist.accent
        case .secondary: return pressed ? Geist.Palette.gray200 : Geist.card
        case .tertiary: return pressed ? Geist.Palette.grayAlpha200 : .clear
        case .destructive: return pressed ? Geist.Palette.red700 : Geist.Palette.red800
        }
    }

    private func borderColor(_ pressed: Bool) -> Color {
        guard variant == .secondary else { return .clear }
        return pressed ? Geist.borderHi : Geist.border
    }

    private var borderWidth: CGFloat { variant == .secondary ? 1 : 0 }
}

struct GeistDivider: View {
    var body: some View {
        Rectangle().fill(Geist.Palette.gray200).frame(height: 1)
    }
}

struct GeistStatusBadge: View {
    let label: LocalizedStringKey
    let isActive: Bool

    var body: some View {
        HStack(spacing: Geist.Spacing.two) {
            Circle()
                .fill(isActive ? Geist.Palette.blue900 : Geist.Palette.gray700)
                .frame(width: 6, height: 6)
            Text(label)
                .font(Geist.caption())
                .foregroundStyle(isActive ? Geist.Palette.blue900 : Geist.Palette.gray900)
        }
        .padding(.horizontal, Geist.Spacing.three)
        .frame(height: Geist.ControlHeight.small)
        .background(isActive ? Geist.Palette.blue100 : Geist.Palette.gray100)
        .clipShape(Capsule())
    }
}

struct GeistSectionLabel: View {
    let number: String
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .textCase(.uppercase)
            .font(Geist.mono(size: 11, relativeTo: .caption))
            .tracking(0.66)
            .foregroundStyle(Geist.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(title)
    }
}

// MARK: - Signal components

/// 44pt circular icon button on a bordered card, used for Back, Activity and
/// Attach in the Signal layouts.
struct SignalCircleButtonStyle: ButtonStyle {
    var diameter: CGFloat = Geist.ControlHeight.medium
    var filled: Color? = nil
    var foreground: Color = Geist.text

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.4, weight: .semibold))
            .foregroundStyle(filled == nil ? foreground : Geist.onAccent)
            .frame(width: diameter, height: diameter)
            .background(filled ?? Geist.card, in: Circle())
            .overlay {
                if filled == nil {
                    Circle().stroke(Geist.border, lineWidth: 1)
                }
            }
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Signal route tile colors by route order, as on the Routes, Capture and
/// Library boards: the first route indigo, the second near-black "ink"
/// (inverted in dark mode), every other route neutral. The Watch payload
/// (`WatchRouteTileStyle.fallback`) and Mac (`MacRouteTile`) use the same order.
enum SignalRouteTileTone: Equatable {
    case primary
    case ink
    case neutral

    static func forRoute(at index: Int?) -> SignalRouteTileTone {
        switch index {
        case 0: .primary
        case 1: .ink
        default: .neutral
        }
    }

    /// Tone for a route by its position among the enabled routes, in the
    /// user's order.
    @MainActor
    static func forRoute(id: String?) -> SignalRouteTileTone {
        guard let id else { return .neutral }
        return forRoute(at: RouteOrderCache.enabledRoutes().firstIndex { $0.id == id })
    }

    /// Tone for a route known only by its display name (Library items).
    @MainActor
    static func forRoute(named name: String?) -> SignalRouteTileTone {
        guard let name else { return .neutral }
        return forRoute(at: RouteOrderCache.enabledRoutes().firstIndex {
            $0.visibleName == name || $0.accessibilityName == name
        })
    }

    /// Decoded enabled routes, re-read only when the stored routes change, so
    /// list rows can resolve tones cheaply.
    @MainActor
    private enum RouteOrderCache {
        private static var data: Data?
        private static var routes: [CapturePreset] = []
        private static var hasLoaded = false

        static func enabledRoutes() -> [CapturePreset] {
            let current = AppConstants.sharedDefaults?.data(forKey: CapturePresetStore.flowsKey)
            if !hasLoaded || current != data {
                data = current
                routes = CapturePresetStore.loadFlows(persistMigrations: false).filter(\.isEnabled)
                hasLoaded = true
            }
            return routes
        }
    }
}

/// Rounded letter tile identifying a route (capture preset).
struct SignalRouteTile: View {
    let letter: String
    var size: CGFloat = 40
    var isPrimary = false
    var circular = false
    /// Near-black ink tile (inverted in dark mode), the Signal "second" route.
    var isInk = false
    /// Explicit route-order tone; overrides `isPrimary` / `isInk` when set.
    var tone: SignalRouteTileTone? = nil

    private var resolvedTone: SignalRouteTileTone {
        tone ?? (isPrimary ? .primary : isInk ? .ink : .neutral)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: circular ? size / 2 : size * 0.3, style: .continuous)
        Text(letter.prefix(1).uppercased())
            .font(.custom("Geist-SemiBold", fixedSize: size * 0.42))
            .foregroundStyle(Self.letterColor(resolvedTone))
            .frame(width: size, height: size)
            .background(Self.fillColor(resolvedTone), in: shape)
            .accessibilityHidden(true)
    }

    static func fillColor(_ tone: SignalRouteTileTone) -> Color {
        switch tone {
        case .primary: Geist.accent
        case .ink: Geist.text
        case .neutral: Geist.well
        }
    }

    static func letterColor(_ tone: SignalRouteTileTone) -> Color {
        switch tone {
        case .primary: Geist.onAccent
        case .ink: Geist.bg
        case .neutral: Geist.text
        }
    }
}

/// Small neutral capsule used for route steps and metadata.
struct SignalChip: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(Geist.caption(.caption))
            .foregroundStyle(Geist.Palette.gray900)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            // Board: #F2F2EE chip in light, #222220 on the #161616 card in dark.
            .background(adaptive("#f2f2ee", "#222220"), in: Capsule())
    }
}

/// Mono uppercase badge such as DEFAULT.
struct SignalBadge: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(Geist.mono(size: 10.5, relativeTo: .caption2))
            .foregroundStyle(Geist.accentText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Geist.accentSoft, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Retained as an API-compatible background while deliberately rendering no
/// decoration. Geist uses whitespace, tonal surfaces, and borders for depth.
struct GeistGridBackground: View {
    var spacing: CGFloat = 52
    var lineOpacity: Double = 0

    var body: some View { Color.clear }
}

struct IdleWaveformView: View {
    private let barCount = 9

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.15)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: Geist.Spacing.one) {
                ForEach(0..<barCount, id: \.self) { index in
                    let phase = time * 2 + Double(index) * 0.55
                    let height = (sin(phase) + 1) / 2 * 22 + 5
                    Capsule()
                        .fill(Geist.Palette.blue700)
                        .frame(width: 3, height: height)
                }
            }
            .frame(height: 28)
        }
        .accessibilityHidden(true)
    }
}

struct TranscribingDotsView: View {
    var body: some View {
        HStack(spacing: Geist.Spacing.three) {
            ProgressView().tint(Geist.Palette.blue700)
            Text("Transcribing…")
                .font(Geist.heading(.title2))
                .foregroundStyle(Geist.text)
        }
    }
}

struct GeistCardModifier: ViewModifier {
    var padding: CGFloat = Geist.Spacing.six

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Geist.card)
            .overlay(
                RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous)
                    .stroke(Geist.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous))
    }
}

extension View {
    func geistCard(padding: CGFloat = Geist.Spacing.six) -> some View {
        modifier(GeistCardModifier(padding: padding))
    }
}

// MARK: - Thoughtful first-run experience

/// An isolated, warmer treatment for onboarding/purchasing. The rest of Geist
/// stays unchanged. Blue ink and charcoal actions retain the app's identity.
enum Thoughtful {
    static let background = Geist.bg
    static let paper = Geist.card
    static let ink = Geist.text
    static let secondary = Geist.muted
    static let rule = Geist.borderHi
    static let introductionKey = "vox.thoughtfulIntroduction.completed.v1"
    /// Welcome artboard's periwinkle (#8A8FFF): the wordmark extension and
    /// bullet dots on the always-dark Welcome page.
    static let welcomeAccent = Color(red: 138 / 255, green: 143 / 255, blue: 1)

    static var title: Font { .system(.largeTitle, design: .serif).weight(.regular) }
}

/// Original vector artwork: an open-ended note and a small growing branch.
/// No assets or drawings from the inspiration site are reproduced.
struct ThoughtfulNoteIllustration: View {
    var compact = false

    var body: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 58, y: 30))
                p.addQuadCurve(to: CGPoint(x: 218, y: 27), control: CGPoint(x: 145, y: 22))
                p.addLine(to: CGPoint(x: 243, y: 53))
                p.addQuadCurve(to: CGPoint(x: 238, y: 166), control: CGPoint(x: 245, y: 115))
                p.addQuadCurve(to: CGPoint(x: 61, y: 170), control: CGPoint(x: 153, y: 178))
                p.addQuadCurve(to: CGPoint(x: 58, y: 30), control: CGPoint(x: 51, y: 99))
                p.closeSubpath()
            }
            .fill(Thoughtful.paper)
            Path { p in
                p.move(to: CGPoint(x: 58, y: 30))
                p.addQuadCurve(to: CGPoint(x: 218, y: 27), control: CGPoint(x: 145, y: 22))
                p.addLine(to: CGPoint(x: 243, y: 53))
                p.addQuadCurve(to: CGPoint(x: 238, y: 166), control: CGPoint(x: 245, y: 115))
                p.addQuadCurve(to: CGPoint(x: 61, y: 170), control: CGPoint(x: 153, y: 178))
                p.addQuadCurve(to: CGPoint(x: 58, y: 30), control: CGPoint(x: 51, y: 99))
                p.move(to: CGPoint(x: 218, y: 27))
                p.addLine(to: CGPoint(x: 216, y: 53))
                p.addLine(to: CGPoint(x: 243, y: 53))
                for y in [76.0, 98, 120] {
                    p.move(to: CGPoint(x: 82, y: y))
                    p.addQuadCurve(to: CGPoint(x: y == 120 ? 166 : 207, y: y - 2), control: CGPoint(x: 140, y: y + 2))
                }
                p.move(to: CGPoint(x: 25, y: 177))
                p.addQuadCurve(to: CGPoint(x: 74, y: 109), control: CGPoint(x: 31, y: 130))
                p.move(to: CGPoint(x: 36, y: 151))
                p.addQuadCurve(to: CGPoint(x: 15, y: 125), control: CGPoint(x: 12, y: 145))
                p.addQuadCurve(to: CGPoint(x: 36, y: 151), control: CGPoint(x: 36, y: 126))
                p.move(to: CGPoint(x: 49, y: 131))
                p.addQuadCurve(to: CGPoint(x: 46, y: 105), control: CGPoint(x: 30, y: 113))
                p.addQuadCurve(to: CGPoint(x: 49, y: 131), control: CGPoint(x: 60, y: 107))
                p.move(to: CGPoint(x: 43, y: 141))
                p.addQuadCurve(to: CGPoint(x: 76, y: 141), control: CGPoint(x: 61, y: 128))
                p.addQuadCurve(to: CGPoint(x: 43, y: 141), control: CGPoint(x: 61, y: 156))
                p.move(to: CGPoint(x: 260, y: 80))
                p.addQuadCurve(to: CGPoint(x: 278, y: 75), control: CGPoint(x: 269, y: 69))
            }
            .stroke(Geist.Palette.blue900.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 300, height: 196)
        .scaleEffect(compact ? 0.42 : 1)
        .frame(height: compact ? 64 : 196)
        .accessibilityHidden(true)
    }
}

/// Signal first-run: a dark "Welcome" page followed by a light "Setup"-style
/// page. Page 0 renders in the dark scheme in both appearances so the Geist
/// tokens resolve to the Welcome artboard's near-black ground and ink.
struct ThoughtfulOnboarding: View {
    var onFinish: () -> Void
    var onHistory: (() -> Void)? = nil
    var initialPage = 0
    @State private var path: [Int] = []
    @State private var isInstallingRoutes = false
    #if os(iOS)
    @State private var vault: VoxVault?
    @State private var isPickingVault = false
    @State private var starterRoutes: Set<StarterRoute> = Set(StarterRoute.allCases.filter(\.isOnByDefault))
    @State private var setupError: String?
    #endif

    private var currentPage: Int { path.last ?? initialPage }

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack(path: $path) {
                page(initialPage)
                    .navigationDestination(for: Int.self) { page($0) }
            }
            // At accessibility sizes the actions scroll with each page (see
            // `inlineActions`) so a tall pinned footer can't crowd out the text.
            if !dynamicTypeSize.isAccessibilitySize {
                footer
                    .environment(\.colorScheme, currentPage == 0 ? .dark : colorScheme)
            }
        }
        .background(
            Thoughtful.background
                .environment(\.colorScheme, currentPage == 0 ? .dark : colorScheme)
                .ignoresSafeArea()
        )
        .tint(Thoughtful.ink)
        #if os(iOS)
        .task { if vault == nil { vault = await VoxVaultStore.current() } }
        #endif
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// "Start capturing": creates the chosen starter routes in the vault, then
    /// hands over to the plans (purchase) step exactly as before.
    private func startCapturing() {
        #if os(iOS)
        guard !isInstallingRoutes else { return }
        guard let vault else {
            if starterRoutes.isEmpty { onFinish() } else { isPickingVault = true }
            return
        }
        isInstallingRoutes = true
        Task { @MainActor in
            defer { isInstallingRoutes = false }
            do {
                try await StarterRouteInstaller.install(
                    StarterRoute.allCases.filter { starterRoutes.contains($0) }, in: vault
                )
                setupError = nil
                onFinish()
            } catch {
                setupError = error.localizedDescription
            }
        }
        #else
        onFinish()
        #endif
    }

    private var footer: some View {
        footerActions
            .frame(maxWidth: 440)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
            .background(Thoughtful.background)
    }

    /// The footer's actions placed at the end of a page's scrolling content,
    /// used instead of the pinned footer at accessibility text sizes.
    @ViewBuilder
    private var inlineActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            footerActions.padding(.top, 32)
        }
    }

    private var footerActions: some View {
        VStack(spacing: 14) {
            Button(currentPage == 0 ? String(localized: "Get started") : String(localized: "Start capturing")) {
                if currentPage == 0 {
                    if path.isEmpty { path.append(1) }
                } else { startCapturing() }
            }
            .buttonStyle(GeistButtonStyle(variant: .primary))
            .disabled(isInstallingRoutes)
            .accessibilityIdentifier(currentPage == 0 ? "onboarding.continue" : "onboarding.plans")
            if currentPage == 0 {
                Text(verbatim: "Open source · AGPL-3.0")
                    .font(Geist.caption())
                    .foregroundStyle(Thoughtful.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func page(_ index: Int) -> some View {
        Group {
            if index == 0 {
                welcomePage
                    .environment(\.colorScheme, .dark)
            } else {
                setupPage
            }
        }
        .id(index)
        .navigationTitle("Vox.md")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(index == 0 ? .dark : nil, for: .navigationBar)
        #endif
        .toolbar {
            // Only the active page contributes tools; pushed pages must not
            // accumulate another History button from their ancestor.
            // The plans are reached through the flow itself (Get started →
            // Setup → Start capturing), so there is no separate skip button.
            if index == currentPage {
                ToolbarItem(placement: .principal) {
                    // Welcome carries the wordmark in its content instead.
                    if index == 0 {
                        Text(verbatim: "").accessibilityHidden(true)
                    } else {
                        wordmark
                            .environment(\.colorScheme, colorScheme)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    if let onHistory {
                        Button("Library", systemImage: "clock", action: onHistory)
                            .accessibilityIdentifier("paywall.existingHistory")
                    }
                }
            }
        }
    }

    /// `vox.md` mono wordmark with the indigo extension.
    private var wordmark: some View {
        wordmark(extensionColor: Geist.accentText)
    }

    private func wordmark(extensionColor: Color) -> some View {
        (Text(verbatim: "vox").foregroundColor(Geist.text)
            + Text(verbatim: ".md").foregroundColor(extensionColor))
            .font(Geist.mono(size: 15, relativeTo: .headline, medium: true))
            .accessibilityLabel(Text(verbatim: "Vox.md"))
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Welcome

    private var welcomePage: some View {
        GeometryReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                wordmark(extensionColor: Thoughtful.welcomeAccent)
                    .padding(.top, 8)

                Text(String(localized: "Say it.\nIt lands in\nMarkdown."))
                    .font(.custom("Geist-SemiBold", size: 46, relativeTo: .largeTitle))
                    .tracking(-1.6)
                    .lineSpacing(-4)
                    .foregroundStyle(Geist.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 48)

                welcomeExample
                    .padding(.top, 36)

                // The board pins the promises just above Get started.
                Spacer(minLength: 40)

                VStack(alignment: .leading, spacing: 10) {
                    welcomeBullet("Transcribed on this device")
                    welcomeBullet("Written to your Obsidian vault or Files")
                    welcomeBullet("Your words are never sent to us")
                }

                inlineActions
            }
            .frame(maxWidth: 440, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
        }
        }
        .background(Thoughtful.background.ignoresSafeArea())
    }

    private var welcomeExample: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 28, height: 28)
                    .background(Geist.recording, in: Circle())
                    .accessibilityHidden(true)
                Text("“Remind me to book flights for Lisbon”")
                    .font(Geist.body(.body))
                    .foregroundStyle(Geist.text.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle()
                .fill(Geist.Palette.gray500)
                .frame(width: 2, height: 18)
                .padding(.leading, 13)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Tasks.md › ## Today")
                    .foregroundStyle(Geist.faint)
                Text("- [ ] Book flights for Lisbon")
                    .foregroundStyle(Geist.text)
            }
            .font(Geist.mono(size: 13, relativeTo: .footnote))
            .lineSpacing(3)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Example: say “Remind me to book flights for Lisbon” and it lands in Tasks.md under Today as a task."))
    }

    private func welcomeBullet(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Thoughtful.welcomeAccent)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(text)
                .font(.custom("Geist-Regular", size: 15, relativeTo: .callout))
                // Welcome is always dark: #C9C9C4 on the near-black ground.
                .foregroundStyle(Geist.text.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Setup

    #if os(iOS)
    private var setupPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { step in
                        Capsule()
                            .fill(step <= 1 ? Geist.text : Geist.well)
                            .frame(height: 4)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Step 2 of 2"))

                Text(String(localized: "Where should\nnotes land?"))
                    .font(.custom("Geist-SemiBold", size: 32, relativeTo: .largeTitle))
                    .tracking(-0.8)
                    .foregroundStyle(Thoughtful.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 28)

                VaultPickerCard(vault: vault, isPicking: $isPickingVault) { picked in
                    vault = picked
                }
                .padding(.top, 20)

                Text("Start with these routes")
                    .font(.custom("Geist-SemiBold", size: 15, relativeTo: .headline))
                    .foregroundStyle(Thoughtful.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 28)
                Text("You can edit or add more any time.")
                    .font(Geist.body(.callout))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Thoughtful.secondary)
                    .padding(.top, 4)

                VStack(spacing: 0) {
                    ForEach(Array(StarterRoute.allCases.enumerated()), id: \.element) { index, route in
                        if index > 0 { GeistDivider() }
                        starterRouteRow(route)
                    }
                }
                .padding(.horizontal, 14)
                .background(Thoughtful.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Geist.border, lineWidth: 1)
                )
                .padding(.top, 12)

                if let setupError {
                    Text(setupError)
                        .font(Geist.caption())
                        .foregroundStyle(Geist.error)
                        .padding(.top, 10)
                } else if vault == nil && !starterRoutes.isEmpty {
                    Text("Choose a folder so these routes know where to write.")
                        .font(Geist.caption())
                        .foregroundStyle(Thoughtful.secondary)
                        .padding(.top, 10)
                }

                inlineActions
            }
            .frame(maxWidth: 440, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Thoughtful.background.ignoresSafeArea())
    }

    /// Setup board row: route tile (ink when chosen), name, mono path and
    /// a trailing indigo checkbox. The whole row toggles.
    private func starterRouteRow(_ route: StarterRoute) -> some View {
        let isOn = starterRoutes.contains(route)
        return Button {
            if isOn { starterRoutes.remove(route) } else { starterRoutes.insert(route) }
        } label: {
            HStack(spacing: 12) {
                SignalRouteTile(letter: route.name, size: 32, isInk: isOn)
                VStack(alignment: .leading, spacing: 1) {
                    Text(route.name)
                        .font(Geist.label(.body))
                        .foregroundStyle(Thoughtful.ink)
                    Text(verbatim: route.pathLabel)
                        .font(Geist.mono(size: 11, relativeTo: .caption))
                        .foregroundStyle(Thoughtful.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isOn ? Geist.accent : Geist.borderHi)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
        .accessibilityIdentifier("onboarding.starter.\(route.rawValue)")
    }
    #else
    private var setupPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "Your words.\nYour own space."))
                    .font(.custom("Geist-SemiBold", size: 32, relativeTo: .largeTitle))
                    .tracking(-0.8)
                    .foregroundStyle(Thoughtful.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 28)

                Text(String(localized: "Plain Markdown, saved to the folders you choose. Voice transcription stays on your device."))
                    .font(Geist.body(.callout))
                    .foregroundStyle(Thoughtful.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                VStack(spacing: 0) {
                    setupRow("Capture a moment in words or voice", systemImage: "waveform", primary: true)
                    GeistDivider()
                    setupRow("Keep notes in your own folders", systemImage: "folder")
                    GeistDivider()
                    setupRow("Read and export your Library anytime", systemImage: "clock")
                }
                .padding(.horizontal, 14)
                .background(Thoughtful.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Geist.border, lineWidth: 1)
                )
                .padding(.top, 24)

                inlineActions
            }
            .frame(maxWidth: 440, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Thoughtful.background.ignoresSafeArea())
    }
    #endif

    private func setupRow(_ title: LocalizedStringKey, systemImage: String, primary: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(primary ? Geist.onAccent : Geist.text)
                .frame(width: 32, height: 32)
                .background(primary ? Geist.accent : Geist.well,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(Geist.label(.body))
                .foregroundStyle(Thoughtful.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}

/// Shared guidance for choosing a destination and saving the first real note.
/// Shown on Capture after unlocking when Setup didn't already pick a folder.
struct FirstNoteGuide: View {
    enum Step {
        case chooseFolder
        case writeNote(folder: String)
        case saved(file: String)
    }

    let step: Step
    let action: () -> Void
    let dismiss: () -> Void

    private var title: String {
        switch step {
        case .chooseFolder: String(localized: "Save your first note")
        case .writeNote: String(localized: "Make it yours")
        case .saved: String(localized: "Your first note is saved")
        }
    }

    private var detail: String {
        switch step {
        case .chooseFolder:
            String(localized: "Choose a folder for your Markdown notes. Nothing is saved until you tap Send.")
        case .writeNote(let folder):
            String(localized: "Type a thought or tap Record, then tap Send to save it in \(folder).")
        case .saved(let file):
            String(localized: "\(file) is ready in your folder.")
        }
    }

    private var actionTitle: String {
        switch step {
        case .chooseFolder: String(localized: "Choose a folder")
        case .writeNote: String(localized: "Write a note")
        case .saved: String(localized: "Open saved note")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Geist.heading(.callout))
                .foregroundStyle(Geist.text)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(Geist.body(.subheadline))
                .foregroundStyle(Geist.muted)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { actions }
                VStack(alignment: .leading, spacing: 12) { actions }
            }
            .padding(.top, 2)
        }
        .padding(Geist.Spacing.four)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Geist.card, in: RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous)
                .stroke(Geist.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture.firstNoteGuide")
    }

    @ViewBuilder private var actions: some View {
        Button(actionTitle, action: action)
            .buttonStyle(GeistButtonStyle(variant: .primary, size: .small))
            .accessibilityIdentifier("capture.firstNoteAction")
        if case .saved = step {
            Button("Done", action: dismiss)
                .font(Geist.label(.subheadline))
                .foregroundStyle(Geist.accentText)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityIdentifier("capture.firstNoteDone")
        }
    }
}
