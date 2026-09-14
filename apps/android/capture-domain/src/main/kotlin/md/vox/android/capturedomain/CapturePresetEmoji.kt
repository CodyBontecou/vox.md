package md.vox.android.capturedomain

/**
 * Input/display policy for a preset's optional emoji, ported from the iOS
 * VoxboardCaptureCore validator. Persisted identity stays lossless so an older
 * Unicode runtime does not erase a newer device's choice.
 *
 * Returns one complete emoji after trimming edge Unicode whitespace and
 * newlines, or null for empty, nonemoji, multiple-choice, or malformed input.
 * Never truncates, adds a variation selector, or rewrites the scalar sequence.
 *
 * Accepts non-ASCII emoji bases (including text-default symbols such as ❤),
 * optional emoji presentation selectors, skin-tone modifiers on eligible bases,
 * ZWJ sequences, paired regional-indicator flags, keycaps, and tag flags.
 * Plain ASCII/digits, standalone modifiers/indicators, explicit text
 * presentation selectors, and unrelated combining marks are rejected.
 *
 * This is structural validation against frozen Unicode property tables (see
 * range tables below), not an emoji catalog or a guarantee that the platform
 * has a composed glyph for every accepted ZWJ/tag/flag sequence. Editors use
 * null to reject a choice; renderers fall back to the preset's symbol.
 */
object CapturePresetEmoji {
    fun normalized(value: String?): String? {
        if (value == null) return null
        val text = value.trim(::isEdgeWhitespace)
        if (text.isEmpty()) return null
        return if (isEmoji(text.codePoints().toArray())) text else null
    }

    private fun isEdgeWhitespace(character: Char): Boolean =
        character == '\n' || character == '\r' || character == '\t' ||
            Character.isWhitespace(character) || Character.isSpaceChar(character)

    private fun isEmoji(scalars: IntArray): Boolean {
        if (scalars.isEmpty()) return false
        val first = scalars[0]

        // Unicode's Emoji property includes #, *, and digits even when they are
        // plain text. Only their complete keycap sequences qualify here.
        if (first == 0x23 || first == 0x2A || first in 0x30..0x39) {
            return scalars.contentEquals(intArrayOf(first, 0x20E3)) ||
                scalars.contentEquals(intArrayOf(first, 0xFE0F, 0x20E3))
        }
        if (isRegionalIndicator(first)) {
            return scalars.size == 2 && scalars.all(::isRegionalIndicator)
        }
        // Subdivision flags: black flag + tag letters/digits + cancel tag.
        if (first == 0x1F3F4 && scalars.size > 2 && scalars.last() == 0xE007F) {
            return scalars.drop(1).dropLast(1).all { it in 0xE0061..0xE007A || it in 0xE0030..0xE0039 }
        }

        // Inspect only after whole-string boundaries. Empty components reject
        // dangling/repeated joiners rather than silently dropping them.
        var start = 0
        while (start <= scalars.size) {
            var joiner = -1
            for (index in start until scalars.size) {
                if (scalars[index] == ZWJ) { joiner = index; break }
            }
            val end = if (joiner == -1) scalars.size else joiner
            if (!isEmojiComponent(scalars, start, end)) return false
            if (joiner == -1) return true
            start = joiner + 1
        }
        return false
    }

    private fun isEmojiComponent(scalars: IntArray, start: Int, end: Int): Boolean {
        if (start >= end) return false
        val base = scalars[start]
        if (base <= 0x7F || !isEmojiScalar(base) || isEmojiModifier(base) || isRegionalIndicator(base)) return false
        var index = start + 1
        if (index < end && scalars[index] == 0xFE0F) index++
        if (index < end && isEmojiModifier(scalars[index])) {
            if (!isEmojiModifierBase(base)) return false
            index++
        }
        return index == end
    }

    private fun isRegionalIndicator(scalar: Int): Boolean = scalar in 0x1F1E6..0x1F1FF

    private const val ZWJ = 0x200D

    private fun inRanges(ranges: LongArray, scalar: Int): Boolean {
        var low = 0
        var high = ranges.size / 2 - 1
        while (low <= high) {
            val middle = (low + high) / 2
            val index = middle * 2
            if (scalar < ranges[index]) {
                high = middle - 1
            } else if (scalar > ranges[index + 1]) {
                low = middle + 1
            } else {
                return true
            }
        }
        return false
    }

    private fun isEmojiScalar(scalar: Int): Boolean = inRanges(EMOJI_RANGES, scalar)
    private fun isEmojiModifier(scalar: Int): Boolean = inRanges(EMOJI_MODIFIER_RANGES, scalar)
    private fun isEmojiModifierBase(scalar: Int): Boolean = inRanges(EMOJI_MODIFIER_BASE_RANGES, scalar)

    // Frozen Unicode property ranges (Emoji, Emoji_Modifier, Emoji_Modifier_Base),
    // generated from the Unicode tables behind the iOS validation runtime
    // (Swift 6.3 toolchain). Validation-only: unseen future scalars are rejected,
    // while any already-persisted emoji keeps rendering losslessly.
// EMOJI: 151 ranges, 1438 scalars
private val EMOJI_RANGES = longArrayOf(0x23L, 0x23L, 0x2aL, 0x2aL, 0x30L, 0x39L, 0xa9L, 0xa9L, 0xaeL, 0xaeL, 0x203cL, 0x203cL, 0x2049L, 0x2049L, 0x2122L, 0x2122L, 0x2139L, 0x2139L, 0x2194L, 0x2199L, 0x21a9L, 0x21aaL, 0x231aL, 0x231bL, 0x2328L, 0x2328L, 0x23cfL, 0x23cfL, 0x23e9L, 0x23f3L, 0x23f8L, 0x23faL, 0x24c2L, 0x24c2L, 0x25aaL, 0x25abL, 0x25b6L, 0x25b6L, 0x25c0L, 0x25c0L, 0x25fbL, 0x25feL, 0x2600L, 0x2604L, 0x260eL, 0x260eL, 0x2611L, 0x2611L, 0x2614L, 0x2615L, 0x2618L, 0x2618L, 0x261dL, 0x261dL, 0x2620L, 0x2620L, 0x2622L, 0x2623L, 0x2626L, 0x2626L, 0x262aL, 0x262aL, 0x262eL, 0x262fL, 0x2638L, 0x263aL, 0x2640L, 0x2640L, 0x2642L, 0x2642L, 0x2648L, 0x2653L, 0x265fL, 0x2660L, 0x2663L, 0x2663L, 0x2665L, 0x2666L, 0x2668L, 0x2668L, 0x267bL, 0x267bL, 0x267eL, 0x267fL, 0x2692L, 0x2697L, 0x2699L, 0x2699L, 0x269bL, 0x269cL, 0x26a0L, 0x26a1L, 0x26a7L, 0x26a7L, 0x26aaL, 0x26abL, 0x26b0L, 0x26b1L, 0x26bdL, 0x26beL, 0x26c4L, 0x26c5L, 0x26c8L, 0x26c8L, 0x26ceL, 0x26cfL, 0x26d1L, 0x26d1L, 0x26d3L, 0x26d4L, 0x26e9L, 0x26eaL, 0x26f0L, 0x26f5L, 0x26f7L, 0x26faL, 0x26fdL, 0x26fdL, 0x2702L, 0x2702L, 0x2705L, 0x2705L, 0x2708L, 0x270dL, 0x270fL, 0x270fL, 0x2712L, 0x2712L, 0x2714L, 0x2714L, 0x2716L, 0x2716L, 0x271dL, 0x271dL, 0x2721L, 0x2721L, 0x2728L, 0x2728L, 0x2733L, 0x2734L, 0x2744L, 0x2744L, 0x2747L, 0x2747L, 0x274cL, 0x274cL, 0x274eL, 0x274eL, 0x2753L, 0x2755L, 0x2757L, 0x2757L, 0x2763L, 0x2764L, 0x2795L, 0x2797L, 0x27a1L, 0x27a1L, 0x27b0L, 0x27b0L, 0x27bfL, 0x27bfL, 0x2934L, 0x2935L, 0x2b05L, 0x2b07L, 0x2b1bL, 0x2b1cL, 0x2b50L, 0x2b50L, 0x2b55L, 0x2b55L, 0x3030L, 0x3030L, 0x303dL, 0x303dL, 0x3297L, 0x3297L, 0x3299L, 0x3299L, 0x1f004L, 0x1f004L, 0x1f0cfL, 0x1f0cfL, 0x1f170L, 0x1f171L, 0x1f17eL, 0x1f17fL, 0x1f18eL, 0x1f18eL, 0x1f191L, 0x1f19aL, 0x1f1e6L, 0x1f1ffL, 0x1f201L, 0x1f202L, 0x1f21aL, 0x1f21aL, 0x1f22fL, 0x1f22fL, 0x1f232L, 0x1f23aL, 0x1f250L, 0x1f251L, 0x1f300L, 0x1f321L, 0x1f324L, 0x1f393L, 0x1f396L, 0x1f397L, 0x1f399L, 0x1f39bL, 0x1f39eL, 0x1f3f0L, 0x1f3f3L, 0x1f3f5L, 0x1f3f7L, 0x1f4fdL, 0x1f4ffL, 0x1f53dL, 0x1f549L, 0x1f54eL, 0x1f550L, 0x1f567L, 0x1f56fL, 0x1f570L, 0x1f573L, 0x1f57aL, 0x1f587L, 0x1f587L, 0x1f58aL, 0x1f58dL, 0x1f590L, 0x1f590L, 0x1f595L, 0x1f596L, 0x1f5a4L, 0x1f5a5L, 0x1f5a8L, 0x1f5a8L, 0x1f5b1L, 0x1f5b2L, 0x1f5bcL, 0x1f5bcL, 0x1f5c2L, 0x1f5c4L, 0x1f5d1L, 0x1f5d3L, 0x1f5dcL, 0x1f5deL, 0x1f5e1L, 0x1f5e1L, 0x1f5e3L, 0x1f5e3L, 0x1f5e8L, 0x1f5e8L, 0x1f5efL, 0x1f5efL, 0x1f5f3L, 0x1f5f3L, 0x1f5faL, 0x1f64fL, 0x1f680L, 0x1f6c5L, 0x1f6cbL, 0x1f6d2L, 0x1f6d5L, 0x1f6d8L, 0x1f6dcL, 0x1f6e5L, 0x1f6e9L, 0x1f6e9L, 0x1f6ebL, 0x1f6ecL, 0x1f6f0L, 0x1f6f0L, 0x1f6f3L, 0x1f6fcL, 0x1f7e0L, 0x1f7ebL, 0x1f7f0L, 0x1f7f0L, 0x1f90cL, 0x1f93aL, 0x1f93cL, 0x1f945L, 0x1f947L, 0x1f9ffL, 0x1fa70L, 0x1fa7cL, 0x1fa80L, 0x1fa8aL, 0x1fa8eL, 0x1fac6L, 0x1fac8L, 0x1fac8L, 0x1facdL, 0x1fadcL, 0x1fadfL, 0x1faeaL, 0x1faefL, 0x1faf8L)
// EMOJI_MODIFIER: 1 ranges, 5 scalars
private val EMOJI_MODIFIER_RANGES = longArrayOf(0x1f3fbL, 0x1f3ffL)
// EMOJI_MODIFIER_BASE: 40 ranges, 134 scalars
private val EMOJI_MODIFIER_BASE_RANGES = longArrayOf(0x261dL, 0x261dL, 0x26f9L, 0x26f9L, 0x270aL, 0x270dL, 0x1f385L, 0x1f385L, 0x1f3c2L, 0x1f3c4L, 0x1f3c7L, 0x1f3c7L, 0x1f3caL, 0x1f3ccL, 0x1f442L, 0x1f443L, 0x1f446L, 0x1f450L, 0x1f466L, 0x1f478L, 0x1f47cL, 0x1f47cL, 0x1f481L, 0x1f483L, 0x1f485L, 0x1f487L, 0x1f48fL, 0x1f48fL, 0x1f491L, 0x1f491L, 0x1f4aaL, 0x1f4aaL, 0x1f574L, 0x1f575L, 0x1f57aL, 0x1f57aL, 0x1f590L, 0x1f590L, 0x1f595L, 0x1f596L, 0x1f645L, 0x1f647L, 0x1f64bL, 0x1f64fL, 0x1f6a3L, 0x1f6a3L, 0x1f6b4L, 0x1f6b6L, 0x1f6c0L, 0x1f6c0L, 0x1f6ccL, 0x1f6ccL, 0x1f90cL, 0x1f90cL, 0x1f90fL, 0x1f90fL, 0x1f918L, 0x1f91fL, 0x1f926L, 0x1f926L, 0x1f930L, 0x1f939L, 0x1f93cL, 0x1f93eL, 0x1f977L, 0x1f977L, 0x1f9b5L, 0x1f9b6L, 0x1f9b8L, 0x1f9b9L, 0x1f9bbL, 0x1f9bbL, 0x1f9cdL, 0x1f9cfL, 0x1f9d1L, 0x1f9ddL, 0x1fac3L, 0x1fac5L, 0x1faf0L, 0x1faf8L)
}
