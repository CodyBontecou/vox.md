import AppKit
import SwiftUI

/// Mac-only brand tokens sampled from the shipped Vox.md app icon.
///
/// Orange is the sole app-authored chromatic accent. State remains legible
/// through symbols and copy, while completion uses neutral ink instead of a
/// second status hue.
enum MacBrand {
    /// Dominant orange sampled from `AppIcon-1024.png` (`#FD9011`).
    static let orange = Color(
        red: 253.0 / 255.0,
        green: 144.0 / 255.0,
        blue: 17.0 / 255.0
    )
    static let onOrange = Color.black
    static let ink = Color.primary
    static let muted = Color.secondary
    static let complete = Color.primary
    static let subtleOrange = orange.opacity(0.12)
    static let orangeBorder = orange.opacity(0.38)

    /// Native selected rows use `MacAccentColor` (`#B45F0A`) so the white
    /// label supplied by AppKit remains readable. Prominent actions keep the
    /// brighter icon orange with black foreground content.
    static let nativeSelectionOrange = Color(
        red: 180.0 / 255.0,
        green: 95.0 / 255.0,
        blue: 10.0 / 255.0
    )

    /// Orange text is darkened in light mode to retain readable contrast.
    static let orangeText = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 253.0 / 255.0, green: 160.0 / 255.0, blue: 47.0 / 255.0, alpha: 1)
            : NSColor(srgbRed: 159.0 / 255.0, green: 91.0 / 255.0, blue: 20.0 / 255.0, alpha: 1)
    })

    static let appKitOrange = NSColor(
        srgbRed: 253.0 / 255.0,
        green: 144.0 / 255.0,
        blue: 17.0 / 255.0,
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

struct MacSidebarBrandView: View {
    var body: some View {
        HStack(spacing: 10) {
            MacAppIconView(size: 28)
                .accessibilityHidden(true)
            Text("Vox.md")
                .font(.headline)
                .foregroundStyle(MacBrand.ink)
        }
        .accessibilityElement(children: .combine)
    }
}
