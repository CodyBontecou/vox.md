import SwiftUI
import Combine
import CoreText

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Geist design system

/// The app's UI source of truth is vendored in `docs/geist/design.md` and
/// `docs/geist/design.dark.md`. Semantic aliases below only point at values
/// defined by those documents; no product-specific colors are introduced.
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
        static let small: CGFloat = 6
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let full: CGFloat = 9_999
    }

    enum ControlHeight {
        static let small: CGFloat = 32
        static let medium: CGFloat = 40
        static let large: CGFloat = 48
    }

    enum Palette {
        // Shared with the keyboard's opaque backdrop for a seamless transition.
        static let background100 = adaptive("#e2e4e8", "#1a1a1c")
        static let background200 = adaptive("#e2e4e8", "#1a1a1c")

        static let gray100 = adaptive("#f2f2f2", "#1a1a1a")
        static let gray200 = adaptive("#ebebeb", "#1f1f1f")
        static let gray300 = adaptive("#e6e6e6", "#292929")
        static let gray400 = adaptive("#eaeaea", "#2e2e2e")
        static let gray500 = adaptive("#c9c9c9", "#454545")
        static let gray600 = adaptive("#a8a8a8", "#878787")
        static let gray700 = adaptive("#8f8f8f", "#8f8f8f")
        static let gray800 = adaptive("#7d7d7d", "#7d7d7d")
        static let gray900 = adaptive("#4d4d4d", "#a0a0a0")
        static let gray1000 = adaptive("#171717", "#ededed")

        static let grayAlpha100 = adaptive("#0000000d", "#ffffff12")
        static let grayAlpha200 = adaptive("#00000015", "#ffffff17")
        static let grayAlpha300 = adaptive("#0000001a", "#ffffff21")
        static let grayAlpha400 = adaptive("#00000014", "#ffffff24")
        static let grayAlpha500 = adaptive("#00000036", "#ffffff3d")
        static let grayAlpha600 = adaptive("#0000003d", "#ffffff82")
        static let grayAlpha700 = adaptive("#00000070", "#ffffff8a")
        static let grayAlpha800 = adaptive("#00000082", "#ffffff78")
        static let grayAlpha900 = adaptive("#000000b3", "#ffffff9c")
        static let grayAlpha1000 = adaptive("#000000e8", "#ffffffeb")

        static let blue100 = adaptive("#f0f7ff", "#06193a")
        static let blue200 = adaptive("#e9f4ff", "#022248")
        static let blue300 = adaptive("#dfefff", "#002f62")
        static let blue400 = adaptive("#cae7ff", "#003674")
        static let blue500 = adaptive("#94ccff", "#00418b")
        static let blue600 = adaptive("#48aeff", "#0090ff")
        static let blue700 = adaptive("#006bff", "#006efe")
        static let blue800 = adaptive("#0059ec", "#005be7")
        static let blue900 = adaptive("#005ff2", "#47a8ff")
        static let blue1000 = adaptive("#002359", "#eaf6ff")

        static let red100 = adaptive("#ffeeef", "#330a11")
        static let red200 = adaptive("#ffe8ea", "#440d13")
        static let red300 = adaptive("#ffe3e4", "#5d0e17")
        static let red400 = adaptive("#ffd7d6", "#6f101b")
        static let red500 = adaptive("#ffb1b3", "#88151f")
        static let red600 = adaptive("#ff676d", "#f32e40")
        static let red700 = adaptive("#fc0035", "#f13242")
        static let red800 = adaptive("#ea001d", "#e2162a")
        static let red900 = adaptive("#d8001b", "#ff565f")
        static let red1000 = adaptive("#47000c", "#ffe9ed")

        static let amber100 = adaptive("#fff6de", "#2a1700")
        static let amber700 = adaptive("#ffae00", "#ffae00")
        static let amber900 = adaptive("#aa4d00", "#ff9300")
        static let amber1000 = adaptive("#561900", "#fff3d5")

        static let green100 = adaptive("#ecfdec", "#002608")
        static let green700 = adaptive("#28a948", "#00ac3a")
        static let green900 = adaptive("#107d32", "#00ca50")
        static let green1000 = adaptive("#003a00", "#d8ffe4")
    }

    // Semantic roles from the documented scale intent.
    static let bg = Palette.background100
    static let surface = Palette.background100
    static let surface2 = Palette.background200
    static let border = Palette.grayAlpha400
    static let borderHi = Palette.grayAlpha500
    static let text = Palette.gray1000
    static let muted = Palette.gray900
    static let faint = Palette.gray700
    static let error = Palette.red900
    static let focus = Palette.blue700
    static let success = Palette.blue900

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
    enum Variant { case primary, secondary, tertiary, destructive }
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
                RoundedRectangle(cornerRadius: Geist.Radius.small, style: .continuous)
                    .stroke(borderColor(configuration.isPressed), lineWidth: borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: Geist.Radius.small, style: .continuous))
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: Geist.Radius.small + 2, style: .continuous)
                        .stroke(Geist.Palette.background100, lineWidth: 2)
                        .padding(-2)
                    RoundedRectangle(cornerRadius: Geist.Radius.small + 4, style: .continuous)
                        .stroke(Geist.focus, lineWidth: 2)
                        .padding(-4)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Geist.Radius.small, style: .continuous))
            .opacity(isEnabled ? 1 : 0.72)
    }

    private var height: CGFloat {
        switch size {
        case .small: return Geist.ControlHeight.small
        case .medium: return Geist.ControlHeight.medium
        case .large: return Geist.ControlHeight.large
        }
    }

    private var horizontalPadding: CGFloat { size == .small ? 6 : (size == .large ? 14 : 10) }

    private var foregroundColor: Color {
        guard isEnabled else { return Geist.Palette.gray700 }
        switch variant {
        case .primary: return Geist.Palette.background100
        case .secondary, .tertiary: return Geist.Palette.gray1000
        case .destructive: return .white
        }
    }

    private func backgroundColor(_ pressed: Bool) -> Color {
        guard isEnabled else { return Geist.Palette.gray100 }
        switch variant {
        case .primary: return pressed ? Geist.Palette.gray900 : Geist.Palette.gray1000
        case .secondary: return pressed ? Geist.Palette.grayAlpha300 : Geist.Palette.background100
        case .tertiary: return pressed ? Geist.Palette.grayAlpha200 : .clear
        case .destructive: return pressed ? Geist.Palette.red700 : Geist.Palette.red800
        }
    }

    private func borderColor(_ pressed: Bool) -> Color {
        guard variant == .secondary else { return .clear }
        return pressed ? Geist.Palette.grayAlpha600 : Geist.Palette.grayAlpha400
    }

    private var borderWidth: CGFloat { variant == .secondary ? 1 : 0 }
}

struct GeistDivider: View {
    var body: some View {
        Rectangle().fill(Geist.Palette.grayAlpha400).frame(height: 1)
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
            .font(Geist.heading(.footnote))
            .foregroundStyle(Geist.Palette.gray1000)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(title)
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
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Geist.Palette.background100)
            .overlay(
                RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous)
                    .stroke(Geist.Palette.grayAlpha400, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous))
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.16 : 0.04),
                radius: 2,
                x: 0,
                y: colorScheme == .dark ? 1 : 2
            )
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
    static let background = adaptive("#e8e6e2", "#1d1c1b")
    static let paper = adaptive("#f5f3ef", "#282725")
    static let ink = Geist.text
    static let secondary = Geist.muted
    static let rule = Geist.borderHi
    static let introductionKey = "vox.thoughtfulIntroduction.completed.v1"

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

struct ThoughtfulOnboarding: View {
    var onFinish: () -> Void
    var onHistory: (() -> Void)? = nil
    var initialPage = 0
    @State private var path: [Int] = []

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack(path: $path) {
                page(initialPage)
                    .navigationDestination(for: Int.self) { page($0) }
            }
            footer
        }
        .background(Thoughtful.background.ignoresSafeArea())
        .tint(Thoughtful.ink)
    }

    private var footer: some View {
        let currentPage = path.last ?? initialPage
        return VStack(spacing: 12) {
            Button("Continue") {
                if currentPage == 0 {
                    if path.isEmpty { path.append(1) }
                } else { onFinish() }
            }
            .buttonStyle(GeistButtonStyle(variant: .primary))
            .accessibilityIdentifier(currentPage == 0 ? "onboarding.continue" : "onboarding.plans")
            Text("No Vox.md account needed. Purchases use your Apple Account.")
                .font(Geist.caption(.caption))
                .foregroundStyle(Thoughtful.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 440)
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Thoughtful.background)
    }

    private func page(_ index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("A LITTLE SPACE FOR YOU")
                        .font(Geist.mono(.caption))
                        .tracking(1)
                    Spacer()
                    Text(verbatim: index == 0 ? "01 / 02" : "02 / 02")
                        .font(Geist.mono(.caption))
                }
                .foregroundStyle(Thoughtful.secondary)

                ThoughtfulNoteIllustration()
                    .scaleEffect(0.85)
                    .frame(height: 168)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                Text(index == 0 ? String(localized: "Catch a thought.\nKeep it close.") : String(localized: "Your words.\nYour own space."))
                    .font(Thoughtful.title)
                    .foregroundStyle(Thoughtful.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(index == 0
                     ? String(localized: "A quick note, a voice memo, a little something you don’t want to lose. Give it a place in Vox.md.")
                     : String(localized: "Plain Markdown, saved to the folders you choose. Voice transcription stays on your device."))
                    .font(Geist.body())
                    .foregroundStyle(Thoughtful.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if index == 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("A thought for later", systemImage: "pencil.line")
                            .font(Geist.caption())
                            .foregroundStyle(Thoughtful.secondary)
                        Text("Take the long way home.")
                            .font(.system(.title3, design: .serif))
                            .foregroundStyle(Thoughtful.ink)
                        Text("Example note · yours can start anywhere")
                            .font(Geist.caption(.caption))
                            .foregroundStyle(Thoughtful.secondary)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Thoughtful.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Capture a moment in words or voice", systemImage: "waveform")
                        Label("Keep notes in your own folders", systemImage: "folder")
                        Label("Read and export your history anytime", systemImage: "clock")
                    }
                    .font(Geist.body(.callout))
                    .foregroundStyle(Thoughtful.ink)
                    .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: 440, alignment: .topLeading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Thoughtful.background.ignoresSafeArea())
        .id(index)
        .navigationTitle("Vox.md")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            // Only the active page contributes tools; pushed pages must not
            // accumulate another History button from their ancestor.
            if index == (path.last ?? initialPage) {
                ToolbarItem(placement: .cancellationAction) {
                    if let onHistory {
                        Button("History", systemImage: "clock", action: onHistory)
                            .accessibilityIdentifier("paywall.existingHistory")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("View plans", action: onFinish)
                        .font(Geist.body(.callout))
                        .accessibilityIdentifier("onboarding.skip")
                }
            }
        }
    }
}
