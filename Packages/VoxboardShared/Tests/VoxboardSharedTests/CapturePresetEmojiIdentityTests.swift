import XCTest
@testable import VoxboardShared

final class CapturePresetEmojiIdentityTests: XCTestCase {
    func test_legacyPresetPayloadAndNullEmojiRetainSymbolFallback() throws {
        for emojiField in ["", #", "emoji":null"#] {
            let data = Data("""
            {"id":"journal","name":"Journal","symbolName":"book"\(emojiField)}
            """.utf8)
            let preset = try JSONDecoder().decode(CapturePreset.self, from: data)
            XCTAssertNil(preset.emoji)
            XCTAssertNil(preset.captureProfile.emoji)
            XCTAssertEqual(preset.symbolName, "book")
            XCTAssertEqual(preset.id, "journal")
            XCTAssertNil(try jsonObject(preset)["emoji"])
        }
    }

    func test_missingSymbolStillUsesExistingDefaultAndEmojiRemainsOptional() throws {
        let preset = try JSONDecoder().decode(
            CapturePreset.self,
            from: Data(#"{"id":"legacy","name":"Legacy"}"#.utf8)
        )
        XCTAssertEqual(preset.symbolName, CapturePresetStore.defaultSymbolName)
        XCTAssertNil(preset.emoji)
        XCTAssertNil(CapturePresetStore.defaultFlow.emoji)
        XCTAssertNil(CapturePresetStore.makeCustomFlow().emoji)
        XCTAssertEqual(CapturePresetStore.generalId, "general")
        XCTAssertEqual(CapturePresetStore.flowsKey, "recordingFlows")
        XCTAssertEqual(CapturePresetStore.selectedFlowIdKey, "selectedRecordingFlowId")
        XCTAssertEqual(CapturePresetProfileStore.profilesKey, CapturePresetStore.flowsKey)
        XCTAssertEqual(CapturePresetProfileStore.selectedCaptureProfileIDKey, "selectedCaptureVoxId")
    }

    func test_composedEmojiPersistsThroughFullPresetProfileAndReference() throws {
        for emoji in ["🇯🇵", "1️⃣", "❤️", "👍🏽", "👩🏽‍💻", "👨‍👩‍👧‍👦"] {
            let preset = CapturePreset(
                id: "journal",
                name: "Journal",
                symbolName: "book",
                emoji: emoji,
                isEnabled: false,
                staticFrontmatter: ["type": "journal"],
                captureDestinationID: UUID()
            )
            let data = try JSONEncoder().encode(preset)
            let decoded = try JSONDecoder().decode(CapturePreset.self, from: data)
            let lightweight = try JSONDecoder().decode(CapturePresetProfile.self, from: data)
            let reference = CapturePresetReference(profile: decoded.captureProfile)

            XCTAssertEqual(decoded, preset)
            XCTAssertEqual(lightweight, preset.captureProfile)
            XCTAssertEqual(lightweight.captureDestinationID, preset.captureDestinationID)
            XCTAssertEqual(Array(try XCTUnwrap(decoded.emoji).utf8), Array(emoji.utf8))
            XCTAssertEqual(Array(try XCTUnwrap(lightweight.emoji).utf8), Array(emoji.utf8))
            XCTAssertEqual(Array(try XCTUnwrap(reference.emoji).utf8), Array(emoji.utf8))
            XCTAssertEqual(reference.id, preset.id)
            XCTAssertEqual(reference.symbolName, "book")
        }
    }

    func test_addingOrRemovingEmojiDoesNotChangeOtherPersistenceKeys() throws {
        var preset = CapturePreset(id: "journal", name: "Journal", symbolName: "book", watchOutputMode: .recordingOnly)
        let originalObject = try jsonObject(preset)
        XCTAssertNil(originalObject["emoji"])

        preset.emoji = "📔"
        var updatedObject = try jsonObject(preset)
        XCTAssertEqual(updatedObject.removeValue(forKey: "emoji") as? String, "📔")
        XCTAssertEqual(NSDictionary(dictionary: updatedObject), NSDictionary(dictionary: originalObject))
        XCTAssertEqual(preset.captureProfile.symbolName, "book", "Watch/system-image surfaces keep their fallback")
        XCTAssertEqual(preset.watchOutputMode, .recordingOnly)

        preset.emoji = nil
        XCTAssertEqual(NSDictionary(dictionary: try jsonObject(preset)), NSDictionary(dictionary: originalObject))
        XCTAssertNil(preset.captureProfile.emoji)
    }

    func test_invalidStoredEmojiDoesNotInvalidatePresetOrRewriteItsSymbol() throws {
        let preset = CapturePreset(id: "journal", name: "Journal", symbolName: "book", emoji: "not an emoji")
        let decoded = try JSONDecoder().decode(CapturePreset.self, from: JSONEncoder().encode(preset))
        XCTAssertEqual(decoded, preset)
        XCTAssertEqual(decoded.captureProfile.emoji, "not an emoji")
        XCTAssertNil(CapturePresetEmoji.normalized(decoded.emoji))
        XCTAssertEqual(decoded.symbolName, "book")
    }

    func test_iconOnlyPresetKeepsNameBlankForVisibleCompactSurfaces() {
        let preset = CapturePreset(id: "icon-only", name: "  \n", symbolName: "book", emoji: "🤓")
        XCTAssertNil(preset.visibleName)
        XCTAssertEqual(preset.accessibilityName, String(localized: "Icon-only Capture Preset", bundle: .main))
        XCTAssertEqual(preset.displayName, String(localized: "Untitled Preset", bundle: .main))
        XCTAssertEqual(preset.shortLabel, "🤓")

        let profile = preset.captureProfile
        XCTAssertNil(profile.visibleName)
        XCTAssertEqual(profile.accessibilityName, "Icon-only Capture Preset")
        XCTAssertEqual(profile.displayName, "Untitled Preset")

        let reference = CapturePresetReference(profile: profile)
        XCTAssertEqual(reference.name, "")
        XCTAssertEqual(reference.emoji, "🤓")
    }

    func test_optionalEmojiFieldDoesNotRelaxExistingStringTypeContract() {
        let data = Data(#"{"id":"journal","name":"Journal","symbolName":"book","emoji":42}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CapturePreset.self, from: data))
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }
}
