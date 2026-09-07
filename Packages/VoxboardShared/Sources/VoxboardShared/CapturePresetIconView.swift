#if canImport(SwiftUI)
import SwiftUI
import VoxboardCaptureCore

/// Decorative preset identity. The enclosing control owns the preset-name
/// accessibility label, selected state, layout, font, and hit target.
public struct CapturePresetIconView: View {
    private let symbolName: String
    private let emoji: String?

    /// Displays a validated emoji or the existing SF Symbol. Empty symbol names
    /// use `waveform`; no symbol catalog or platform-specific lookup is required.
    /// Invalid emoji never replaces or mutates the stored fallback symbol.
    public init(symbolName: String, emoji: String? = nil) {
        let trimmedSymbol = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.symbolName = trimmedSymbol.isEmpty ? "waveform" : trimmedSymbol
        self.emoji = CapturePresetEmoji.normalized(emoji)
    }

    public var body: some View {
        Group {
            if let emoji {
                Text(verbatim: emoji)
            } else {
                Image(systemName: symbolName)
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
