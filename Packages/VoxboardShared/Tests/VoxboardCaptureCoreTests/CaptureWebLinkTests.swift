import XCTest
@testable import VoxboardCaptureCore

final class CaptureWebLinkTests: XCTestCase {
    func testRejectsIncompleteAndNonWebLinks() throws {
        for value in ["https://", "http:", "https:example.com", "https:///notes", "https://?q=notes", "file:///notes", "mailto:a@example.com", "//example.com", "https://exa%20mple.com", "https://exa%0Ample.com"] {
            XCTAssertFalse(CaptureWebLink.isValid(try XCTUnwrap(URL(string: value))), value)
        }
    }

    func testAcceptsWebHostsAndPreservesURLContent() throws {
        for value in ["https://example.com/a_(b)?q=тест#é", "HTTP://example.com", "http://localhost:8080/notes", "http://127.0.0.1/", "http://[::1]/", "https://例え.テスト/ノート"] {
            XCTAssertTrue(CaptureWebLink.isValid(try XCTUnwrap(URL(string: value))), value)
        }
    }
}
