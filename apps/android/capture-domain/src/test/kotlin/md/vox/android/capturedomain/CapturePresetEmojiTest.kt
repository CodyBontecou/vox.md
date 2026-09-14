package md.vox.android.capturedomain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CapturePresetEmojiTest {
    @Test fun singleEmojiAndVariationSequencesPreserveExactScalarSequence() {
        for (emoji in listOf("📝", "🙂", "☕", "❤", "❤️", "☺️", "©️", "™️")) {
            assertEquals(emoji, CapturePresetEmoji.normalized(emoji))
        }
    }

    @Test fun flagsRemainOneCompleteCharacter() {
        for (emoji in listOf("🇺🇸", "🇯🇵", "🇺🇳")) {
            assertEquals(emoji, CapturePresetEmoji.normalized(emoji))
        }
    }

    @Test fun keycapsAllowOptionalEmojiPresentationSelector() {
        for (base in "0123456789#*") {
            assertEquals("$base\u20E3", CapturePresetEmoji.normalized("$base\u20E3"))
            assertEquals("$base\uFE0F\u20E3", CapturePresetEmoji.normalized("$base\uFE0F\u20E3"))
        }
    }

    @Test fun skinTonesAndJoinedFamiliesAreNotScalarTruncated() {
        for (emoji in listOf(
            "👍🏽", "👋🏻", "🧑🏿", "☝🏾", "✌️🏿", "👩🏽‍💻", "👨‍👩‍👧‍👦",
            "🏳️‍🌈", "🏴‍☠️", "👩‍❤️‍💋‍👩", "🧑🏿‍🤝‍🧑🏻",
        )) {
            assertEquals(emoji, CapturePresetEmoji.normalized(emoji))
        }
    }

    @Test fun subdivisionTagFlagPreservesInvisibleTagScalars() {
        // Black flag + tag letters g,b,e,n,g + cancel tag; tag scalars live above the BMP.
        val england = "\uD83C\uDFF4\uDB40\uDC67\uDB40\uDC62\uDB40\uDC65\uDB40\uDC6E\uDB40\uDC67\uDB40\uDC7F"
        assertEquals(england, CapturePresetEmoji.normalized(england))
    }

    @Test fun onlyEdgeWhitespaceIsTrimmed() {
        val emoji = "👩🏽‍💻"
        assertEquals(emoji, CapturePresetEmoji.normalized("\t\n\u00A0$emoji\u3000\r\n"))
        assertNull(CapturePresetEmoji.normalized("👩 🏽‍💻"))
        assertNull(CapturePresetEmoji.normalized("📝\n🙂"))
    }

    @Test fun nullEmptyNonEmojiAndMultipleChoicesAreRejected() {
        for (value in listOf(null, "", " \t\n", "word", "é", "中", "→", "📝🙂", "🇺🇸🇯🇵", "👩🏽‍💻x")) {
            assertNull("Unexpected choice: $value", CapturePresetEmoji.normalized(value))
        }
    }

    @Test fun noPlainASCIICharacterQualifiesIncludingEmojiCapableDigits() {
        for (codePoint in 0..127) {
            assertNull(CapturePresetEmoji.normalized(String(Character.toChars(codePoint))))
        }
        for (base in "0123456789#*A") {
            assertNull(CapturePresetEmoji.normalized("$base\uFE0F"))
        }
    }

    @Test fun standaloneComponentsAndMalformedSequencesAreRejected() {
        for (value in listOf(
            "🏽", "🇺", "\uFE0F", "\u20E3", "\u200D",
            "🙂\u0301", "a\uFE0F", "🙂\uFE0E", "❤\uFE0E",
            "🙂\uFE0F\uFE0F", "🍎🏽", "👍🏽🏿",
            "👩\u200D", "👩\u200D\u200D💻", "👩\u200DA",
            "\uD83C\uDFF4\uDB40\uDC67\uDB40\uDC62", "\uD83C\uDFF4\uDB40\uDC7F",
        )) {
            assertNull("Unexpected sequence: $value", CapturePresetEmoji.normalized(value))
        }
    }

    @Test fun normalizationIsIdempotentAndDoesNotChooseTheFirstEmoji() {
        val normalized = CapturePresetEmoji.normalized("  👨‍👩‍👧‍👦  ")
        assertEquals("👨‍👩‍👧‍👦", normalized)
        assertEquals(normalized, CapturePresetEmoji.normalized(normalized))
        assertNull(CapturePresetEmoji.normalized("  👨‍👩‍👧‍👦 📝  "))
    }
}
