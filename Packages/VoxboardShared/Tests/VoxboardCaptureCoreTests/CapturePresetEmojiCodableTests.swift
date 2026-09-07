import XCTest
@testable import VoxboardCaptureCore

final class CapturePresetEmojiCodableTests: XCTestCase {
    func test_legacySymbolOnlyProfileAndReferenceDecodeWithoutEmoji() throws {
        let data = Data(#"{"id":"journal","name":"Journal","symbolName":"book"}"#.utf8)
        let profile = try JSONDecoder().decode(CapturePresetProfile.self, from: data)
        let reference = try JSONDecoder().decode(CapturePresetReference.self, from: data)

        XCTAssertNil(profile.emoji)
        XCTAssertNil(reference.emoji)
        XCTAssertEqual(profile.symbolName, "book")
        XCTAssertEqual(reference.symbolName, "book")
        XCTAssertEqual(reference.id, profile.id)
        XCTAssertEqual(CapturePresetReference(profile: profile), reference)
    }

    func test_missingProfileSymbolKeepsLegacyWaveformFallback() throws {
        let data = Data(#"{"id":"legacy","name":"Legacy"}"#.utf8)
        let profile = try JSONDecoder().decode(CapturePresetProfile.self, from: data)
        XCTAssertEqual(profile.symbolName, "waveform")
        XCTAssertNil(profile.emoji)
        // Reference decoding has always required its symbol; do not relax that
        // unrelated contract while adding an optional field.
        XCTAssertThrowsError(try JSONDecoder().decode(CapturePresetReference.self, from: data))
    }

    func test_nilEmojiIsOmittedByBothSynthesizedEncoders() throws {
        let profile = CapturePresetProfile(id: "journal", name: "Journal", symbolName: "book")
        let reference = CapturePresetReference(id: profile.id, name: profile.name, symbolName: profile.symbolName)
        let profileObject = try jsonObject(profile)
        let referenceObject = try jsonObject(reference)

        XCTAssertNil(profileObject["emoji"])
        XCTAssertNil(referenceObject["emoji"])
        XCTAssertEqual(Set(referenceObject.keys), ["id", "name", "symbolName"])
        XCTAssertEqual(profileObject["id"] as? String, "journal")
        XCTAssertEqual(profileObject["symbolName"] as? String, "book")
    }

    func test_explicitNullEmojiDecodesNilAndReencodesAbsent() throws {
        let data = Data(#"{"id":"journal","name":"Journal","symbolName":"book","emoji":null}"#.utf8)
        let profile = try JSONDecoder().decode(CapturePresetProfile.self, from: data)
        let reference = try JSONDecoder().decode(CapturePresetReference.self, from: data)
        XCTAssertNil(profile.emoji)
        XCTAssertNil(reference.emoji)
        XCTAssertNil(try jsonObject(profile)["emoji"])
        XCTAssertNil(try jsonObject(reference)["emoji"])
    }

    func test_composedEmojiRoundTripsAndPropagatesIntoReference() throws {
        for emoji in ["🇯🇵", "1️⃣", "❤️", "👍🏽", "👩🏽‍💻", "👨‍👩‍👧‍👦"] {
            let profile = CapturePresetProfile(
                id: "journal",
                name: "  Journal  ",
                symbolName: "book",
                emoji: emoji,
                isEnabled: false,
                staticFrontmatter: ["type": "journal"],
                captureDestinationID: UUID()
            )
            let decoded = try JSONDecoder().decode(CapturePresetProfile.self, from: JSONEncoder().encode(profile))
            let reference = CapturePresetReference(profile: decoded)
            let decodedReference = try JSONDecoder().decode(
                CapturePresetReference.self,
                from: JSONEncoder().encode(reference)
            )

            XCTAssertEqual(decoded, profile)
            XCTAssertEqual(decodedReference, reference)
            XCTAssertEqual(reference.name, "Journal")
            XCTAssertEqual(reference.id, profile.id)
            XCTAssertEqual(reference.symbolName, "book")
            XCTAssertEqual(Array(try XCTUnwrap(decoded.emoji).utf8), Array(emoji.utf8))
            XCTAssertEqual(Array(try XCTUnwrap(decodedReference.emoji).utf8), Array(emoji.utf8))
        }
    }

    func test_emojiChangesOnlyTheOptionalIdentityKeyAndSnapshotStaysIndependent() throws {
        var profile = CapturePresetProfile(id: "journal", name: "Journal", symbolName: "book")
        let originalObject = try jsonObject(profile)
        profile.emoji = "📔"
        let reference = CapturePresetReference(profile: profile)
        var updatedObject = try jsonObject(profile)
        XCTAssertEqual(updatedObject.removeValue(forKey: "emoji") as? String, "📔")
        XCTAssertEqual(NSDictionary(dictionary: updatedObject), NSDictionary(dictionary: originalObject))

        profile.emoji = nil
        XCTAssertEqual(reference.emoji, "📔")
        XCTAssertEqual(profile.symbolName, reference.symbolName)
        XCTAssertNil(try jsonObject(profile)["emoji"])
    }

    func test_unvalidatedStoredStringsRemainLosslessWithoutDamagingFallback() throws {
        // Persistence is not a Unicode-version-dependent migration. Consumers
        // validate at the input/render boundary and keep the symbol usable.
        for rawValue in ["not an emoji", "📝🙂", " \t👩🏽‍💻\n"] {
            let profile = CapturePresetProfile(id: "journal", name: "Journal", symbolName: "book", emoji: rawValue)
            let decoded = try JSONDecoder().decode(CapturePresetProfile.self, from: JSONEncoder().encode(profile))
            let reference = CapturePresetReference(profile: decoded)
            let decodedReference = try JSONDecoder().decode(
                CapturePresetReference.self,
                from: JSONEncoder().encode(reference)
            )
            XCTAssertEqual(Array(try XCTUnwrap(decoded.emoji).utf8), Array(rawValue.utf8))
            XCTAssertEqual(decodedReference.emoji, rawValue)
            XCTAssertEqual(decodedReference.symbolName, "book")
            XCTAssertEqual(CapturePresetEmoji.normalized(decoded.emoji), CapturePresetEmoji.normalized(rawValue))
        }
    }

    func test_wrongEmojiJSONTypeDoesNotSilentlyMaskCorruption() {
        let data = Data(#"{"id":"journal","name":"Journal","symbolName":"book","emoji":42}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CapturePresetProfile.self, from: data))
        XCTAssertThrowsError(try JSONDecoder().decode(CapturePresetReference.self, from: data))
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }
}
