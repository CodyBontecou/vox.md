import Foundation
import VoxboardShared
import XCTest
@testable import Voxboard

@MainActor
final class LibrarySearchTests: XCTestCase {
    func testDeliveredTextUsesTheSameUnicodeSearchAsTranscripts() {
        let id = UUID()
        let text = "İyi uyudum. Résumé Ｖｏｘ [literal]"
        let delivered = LibraryItem(id: id, content: CaptureLibraryContent(requestID: id, text: text))
        let transcript = LibraryItem(id: UUID(), transcript: Transcript(text: text, duration: 0, modelUsed: "test", language: "tr"))

        for query in ["  İYİ  uyudum  ", "resume", "Vox", "[literal]", "\n \t", "missing", ".*"] {
            XCTAssertEqual(delivered.matches(query), transcript.matches(query), "Search differs for \(query)")
        }
        XCTAssertTrue(delivered.matches("İYİ uyudum"))
        XCTAssertTrue(delivered.matches("resume Vox"))
        XCTAssertFalse(delivered.matches(".*"))
    }
}
