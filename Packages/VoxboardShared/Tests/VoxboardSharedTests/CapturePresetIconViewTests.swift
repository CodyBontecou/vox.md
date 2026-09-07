#if canImport(SwiftUI) && (os(iOS) || os(macOS))
import SwiftUI
import XCTest
@testable import VoxboardShared

@MainActor
final class CapturePresetIconViewTests: XCTestCase {
    func test_emojiRendersAsTextRatherThanTheFallbackSymbol() throws {
        let emoji = "👩🏽‍💻"
        let icon = try pixels(CapturePresetIconView(symbolName: "book", emoji: " \(emoji)\n"))
        XCTAssertEqual(icon, try pixels(Text(verbatim: emoji)))
        XCTAssertNotEqual(icon, try pixels(Image(systemName: "book")))
    }

    func test_nilAndInvalidEmojiRenderTheExistingSymbol() throws {
        let symbol = try pixels(Image(systemName: "book"))
        for emoji: String? in [nil, "", "words", "1", "#", "📝🙂", "🙂\u{FE0E}"] {
            XCTAssertEqual(try pixels(CapturePresetIconView(symbolName: "book", emoji: emoji)), symbol)
        }
    }

    func test_blankSymbolNameHasAUsableWaveformFallback() throws {
        XCTAssertEqual(
            try pixels(CapturePresetIconView(symbolName: " \n", emoji: "invalid")),
            try pixels(Image(systemName: "waveform"))
        )
    }

    private func pixels<V: View>(_ view: V) throws -> Data {
        let renderer = ImageRenderer(content: view
            .font(.system(size: 30))
            .foregroundStyle(.black)
            .frame(width: 64, height: 64)
            .background(.white)
            .environment(\.colorScheme, .light))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "The real SwiftUI body must render, not merely initialize")
        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 64)
        let data = try XCTUnwrap(image.dataProvider?.data)
        return data as Data
    }
}
#endif
