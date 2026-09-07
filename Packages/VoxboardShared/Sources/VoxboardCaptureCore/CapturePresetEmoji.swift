import Foundation

/// Input/display policy for a preset's optional emoji. Persisted identity stays
/// lossless so an older Unicode runtime does not erase a newer device's choice.
public enum CapturePresetEmoji {
    /// Returns one complete emoji `Character` after trimming edge whitespace and
    /// newlines, or nil for empty, nonemoji, multiple-choice, or malformed input.
    /// Never truncates, adds a variation selector, or rewrites the scalar sequence.
    ///
    /// Accepts non-ASCII emoji bases (including text-default symbols such as ❤),
    /// optional emoji presentation selectors, skin-tone modifiers on eligible
    /// bases, ZWJ sequences, paired regional-indicator flags, keycaps, and tag
    /// flags. Plain ASCII/digits, standalone modifiers/indicators, explicit text
    /// presentation selectors, and unrelated combining marks are rejected.
    ///
    /// This is structural validation using the runtime's Unicode properties,
    /// not an emoji catalog or a guarantee that the platform has a composed
    /// glyph for every accepted ZWJ/tag/flag sequence. Editors can use nil to
    /// reject a choice; renderers should use the preset's existing SF Symbol.
    public static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count == 1, let character = text.first,
              isEmoji(character) else { return nil }
        return text
    }

    private static func isEmoji(_ character: Character) -> Bool {
        let scalars = Array(character.unicodeScalars)
        guard let first = scalars.first else { return false }

        // Unicode's Emoji property includes #, *, and digits even when they are
        // plain text. Only their complete keycap sequences qualify here.
        if first.value == 0x23 || first.value == 0x2A || (0x30...0x39).contains(first.value) {
            return scalars.map(\.value) == [first.value, 0x20E3]
                || scalars.map(\.value) == [first.value, 0xFE0F, 0x20E3]
        }
        if isRegionalIndicator(first) {
            return scalars.count == 2 && scalars.allSatisfy(isRegionalIndicator)
        }
        // Subdivision flags: black flag + tag letters/digits + cancel tag.
        if first.value == 0x1F3F4, scalars.count > 2,
           scalars.last?.value == 0xE007F {
            return scalars.dropFirst().dropLast().allSatisfy {
                (0xE0061...0xE007A).contains($0.value) || (0xE0030...0xE0039).contains($0.value)
            }
        }

        // Inspect only after the Character boundary check. Empty components
        // reject dangling/repeated joiners rather than silently dropping them.
        return scalars.split(omittingEmptySubsequences: false, whereSeparator: { $0.value == 0x200D })
            .allSatisfy(isEmojiComponent)
    }

    private static func isEmojiComponent(_ scalars: ArraySlice<Unicode.Scalar>) -> Bool {
        guard let base = scalars.first,
              base.value > 0x7F, base.properties.isEmoji,
              !base.properties.isEmojiModifier,
              !isRegionalIndicator(base) else { return false }
        var remainder = scalars.dropFirst()
        if remainder.first?.value == 0xFE0F {
            remainder = remainder.dropFirst()
        }
        if let modifier = remainder.first, modifier.properties.isEmojiModifier {
            guard base.properties.isEmojiModifierBase else { return false }
            remainder = remainder.dropFirst()
        }
        return remainder.isEmpty
    }

    private static func isRegionalIndicator(_ scalar: Unicode.Scalar) -> Bool {
        (0x1F1E6...0x1F1FF).contains(scalar.value)
    }
}
