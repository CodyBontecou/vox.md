import XCTest
@testable import VoxboardCaptureCore

final class CapturePresetEmojiTests: XCTestCase {
    func test_singleEmojiAndVariationSequencesPreserveExactBytes() throws {
        for emoji in ["📝", "🙂", "☕", "❤", "❤️", "☺️", "©️", "™️"] {
            try assertAccepted(emoji)
        }
    }

    func test_flagsRemainOneCompleteCharacter() throws {
        for emoji in ["🇺🇸", "🇯🇵", "🇺🇳"] {
            try assertAccepted(emoji)
        }
    }

    func test_keycapsAllowOptionalEmojiPresentationSelector() throws {
        for base in "0123456789#*" {
            try assertAccepted("\(base)\u{20E3}")
            try assertAccepted("\(base)\u{FE0F}\u{20E3}")
        }
    }

    func test_skinTonesAndJoinedFamiliesAreNotScalarTruncated() throws {
        for emoji in [
            "👍🏽", "👋🏻", "🧑🏿", "☝🏾", "✌️🏿", "👩🏽‍💻", "👨‍👩‍👧‍👦",
            "🏳️‍🌈", "🏴‍☠️", "👩‍❤️‍💋‍👩", "🧑🏿‍🤝‍🧑🏻",
        ] {
            try assertAccepted(emoji)
        }
    }

    func test_subdivisionTagFlagPreservesInvisibleTagScalars() throws {
        let england = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
        try assertAccepted(england)
    }

    func test_onlyEdgeWhitespaceIsTrimmed() throws {
        let emoji = "👩🏽‍💻"
        let value = try XCTUnwrap(CapturePresetEmoji.normalized("\t\n\u{00A0}\(emoji)\u{3000}\r\n"))
        XCTAssertEqual(Array(value.utf8), Array(emoji.utf8))
        XCTAssertNil(CapturePresetEmoji.normalized("👩 🏽‍💻"))
        XCTAssertNil(CapturePresetEmoji.normalized("📝\n🙂"))
    }

    func test_nilEmptyNonemojiAndMultipleChoicesAreRejected() {
        let values: [String?] = [nil, "", " \t\n", "word", "é", "中", "→", "📝🙂", "🇺🇸🇯🇵", "👩🏽‍💻x"]
        for value in values {
            XCTAssertNil(CapturePresetEmoji.normalized(value), "Unexpected choice: \(String(describing: value))")
        }
    }

    func test_noPlainASCIICharacterQualifiesIncludingEmojiCapableDigits() {
        for value in UInt8.min...127 {
            XCTAssertNil(CapturePresetEmoji.normalized(String(Unicode.Scalar(value))))
        }
        for base in "0123456789#*A" {
            XCTAssertNil(CapturePresetEmoji.normalized("\(base)\u{FE0F}"))
        }
    }

    func test_standaloneComponentsAndMalformedSequencesAreRejected() {
        for value in [
            "🏽", "🇺", "\u{FE0F}", "\u{20E3}", "\u{200D}",
            "🙂\u{0301}", "a\u{FE0F}", "🙂\u{FE0E}", "❤\u{FE0E}",
            "🙂\u{FE0F}\u{FE0F}", "🍎🏽", "👍🏽🏿",
            "👩\u{200D}", "👩\u{200D}\u{200D}💻", "👩\u{200D}A",
            "\u{1F3F4}\u{E0067}\u{E0062}", "\u{1F3F4}\u{E007F}",
        ] {
            XCTAssertNil(CapturePresetEmoji.normalized(value), "Unexpected sequence: \(Array(value.unicodeScalars))")
        }
    }

    func test_normalizationIsIdempotentAndDoesNotChooseTheFirstEmoji() throws {
        let normalized = try XCTUnwrap(CapturePresetEmoji.normalized("  👨‍👩‍👧‍👦  "))
        XCTAssertEqual(CapturePresetEmoji.normalized(normalized), normalized)
        XCTAssertNil(CapturePresetEmoji.normalized("  👨‍👩‍👧‍👦 📝  "))
    }

    private func assertAccepted(_ emoji: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(emoji.count, 1, file: file, line: line)
        let normalized = try XCTUnwrap(CapturePresetEmoji.normalized(emoji), file: file, line: line)
        // Swift String equality is canonically equivalent; byte equality also
        // guards against accidental selector/modifier/tag/ZWJ rewriting.
        XCTAssertEqual(Array(normalized.utf8), Array(emoji.utf8), file: file, line: line)
    }
}
