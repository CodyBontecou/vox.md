import Foundation
import XCTest
@testable import VoxboardShared

final class CapturePresetAudioFilenameTests: XCTestCase {
    func test_allTokensUseExplicitCalendarLocaleAndTimeZone() throws {
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let context = makeContext(timeZone: utc)

        let filename = CapturePresetAudioFilename.preferredFilename(
            template: "{timestamp}_{date}_{time}_{YR}_{id}_{id8}_{preset}_{original}.typed",
            context: context,
            sourceExtension: "M4A"
        )

        XCTAssertEqual(
            filename,
            "2024-01-02-030405_2024-01-02_030405_24_abcdef12-3456-7890-abcd-ef1234567890_abcdef12_Daily-Notes_Original-Take.final.m4a"
        )
    }

    func test_timeTokensHonorExplicitTimeZone() throws {
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let filename = CapturePresetAudioFilename.preferredFilename(
            template: "{timestamp}-{date}-{time}",
            context: makeContext(timeZone: losAngeles),
            sourceExtension: "wav"
        )

        XCTAssertEqual(filename, "2024-01-01-190405-2024-01-01-190405.wav")
    }

    func test_typedExtensionIsRemovedAndActualSourceExtensionAlwaysWins() throws {
        let context = makeContext(timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0)))

        XCTAssertEqual(
            CapturePresetAudioFilename.preferredFilename(
                template: "voice.aiff",
                context: context,
                sourceExtension: "WAV"
            ),
            "voice.wav"
        )
        XCTAssertEqual(
            CapturePresetAudioFilename.preferredFilename(
                template: "{original}.mp3",
                context: context,
                sourceExtension: "m4a"
            ),
            "Original-Take.final.m4a"
        )
    }

    func test_separatorsTraversalAndControlsCannotProduceUnsafeComponent() throws {
        var context = makeContext(timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0)))
        context.presetName = "../Dreams/\u{0001}Ideas"
        let filename = try XCTUnwrap(CapturePresetAudioFilename.preferredFilename(
            template: "../../{preset}\\{original}.wav",
            context: context,
            sourceExtension: "m4a"
        ))

        XCTAssertEqual(filename, (filename as NSString).lastPathComponent)
        XCTAssertFalse(filename.contains("/"))
        XCTAssertFalse(filename.contains("\\"))
        XCTAssertFalse(filename.contains(".."))
        XCTAssertFalse(filename.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains))
        XCTAssertTrue(filename.hasSuffix(".m4a"))
    }

    func test_dotOnlyOrControlOnlyRenderFallsBackDeterministically() throws {
        let context = makeContext(timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0)))

        let filename = CapturePresetAudioFilename.preferredFilename(
            template: "../\\\u{0000}\n...",
            context: context,
            sourceExtension: "wav"
        )

        XCTAssertEqual(filename, "recording-2024-01-02-030405-abcdef12.wav")
    }

    func test_utf8BoundKeepsWholeExtendedGraphemes() throws {
        let family = "👨‍👩‍👧‍👦"
        let presetName = String(repeating: family, count: 100)
        var context = makeContext(timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0)))
        context.presetName = presetName

        let filename = try XCTUnwrap(CapturePresetAudioFilename.preferredFilename(
            template: "{preset}",
            context: context,
            sourceExtension: "m4a"
        ))
        let base = (filename as NSString).deletingPathExtension

        XCTAssertLessThanOrEqual(base.utf8.count, CapturePresetAudioFilename.maximumBaseUTF8ByteCount)
        XCTAssertEqual(base, String(presetName.prefix(base.count)))
        XCTAssertTrue(base.hasSuffix(family))
    }

    func test_unknownTokensDeliberatelyRemainSafeLiterals() throws {
        let context = makeContext(timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0)))

        let filename = CapturePresetAudioFilename.preferredFilename(
            template: "voice-{future}-{id8}",
            context: context,
            sourceExtension: "wav"
        )

        XCTAssertEqual(filename, "voice-{future}-abcdef12.wav")
    }

    func test_emptyTemplateReturnsNilSoCallersKeepLegacyName() throws {
        let context = makeContext(timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0)))

        XCTAssertNil(CapturePresetAudioFilename.preferredFilename(
            template: "  \n ",
            context: context,
            sourceExtension: "wav"
        ))
    }

    private func makeContext(timeZone: TimeZone) -> CapturePresetAudioFilenameContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let createdAt = calendar.date(from: DateComponents(
            year: 2024,
            month: 1,
            day: 2,
            hour: 3,
            minute: 4,
            second: 5
        ))!
        return CapturePresetAudioFilenameContext(
            identifier: "ABCDEF12-3456-7890-ABCD-EF1234567890",
            createdAt: createdAt,
            presetName: "Daily Notes",
            originalFilename: "Original Take.final.wav",
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone
        )
    }
}
