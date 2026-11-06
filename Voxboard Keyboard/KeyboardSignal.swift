import CoreText
import SwiftUI

/// Signal tokens for the keyboard extension. `GeistTheme` is app-only, so the
/// keyboard mirrors the subset it needs. The Signal keyboard is always the dark
/// #121212 ground, independent of the host app's appearance.
enum KeyboardSignal {
    // MARK: Palette

    /// Keyboard ground #121212.
    static let ground = Color(hex: 0x121212)
    /// Raised key / chip fill #242424.
    static let key = Color(hex: 0x242424)
    /// Primary ink #F4F4F1 (also the selected segment fill).
    static let ink = Color(hex: 0xF4F4F1)
    /// Ink on a light (selected) segment #121212.
    static let inkOnLight = Color(hex: 0x121212)
    /// Secondary label #B4B4AF.
    static let secondary = Color(hex: 0xB4B4AF)
    /// Muted text #8E8E89.
    static let muted = Color(hex: 0x8E8E89)
    /// Volatile / faint text #5F5F5B.
    static let faint = Color(hex: 0x5F5F5B)
    /// Recording red #F0474A — also used for errors.
    static let red = Color(hex: 0xF0474A)

    // MARK: Typography

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = "Geist-SemiBold"
        case .medium: name = "Geist-Medium"
        default: name = "Geist-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    static func mono(_ size: CGFloat, medium: Bool = false, relativeTo style: Font.TextStyle = .footnote) -> Font {
        .custom(medium ? "GeistMono-Medium" : "GeistMono-Regular", size: size, relativeTo: style)
    }

    // MARK: Fonts

    private static var didRegisterFonts = false

    /// Registers the Geist faces bundled in the extension for this process.
    /// Extensions do not inherit the containing app's `UIAppFonts`.
    static func registerFonts() {
        guard !didRegisterFonts else { return }
        didRegisterFonts = true
        let bundle = Bundle(for: KeyboardViewController.self)
        for name in ["Geist-Regular", "Geist-Medium", "Geist-SemiBold", "GeistMono-Regular", "GeistMono-Medium"] {
            guard let url = bundle.url(forResource: name, withExtension: "ttf")
                ?? bundle.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
