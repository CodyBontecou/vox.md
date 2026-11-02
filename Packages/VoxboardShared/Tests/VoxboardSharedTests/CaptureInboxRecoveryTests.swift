import Foundation
import XCTest
import VoxboardCaptureCore
@testable import VoxboardShared

final class CaptureInboxRecoveryTests: XCTestCase {
    func test_headingsSkipFencedCodeAndKeepLevels() {
        let markdown = """
        # Tasks
        ## Today
        ```
        ## Not a heading
        ```
        ### Later ###
        #NoSpace
        """
        let headings = CaptureInboxRecovery.headings(inMarkdown: markdown)
        XCTAssertEqual(headings.map(\.title), ["Tasks", "Today", "Later"])
        XCTAssertEqual(headings.map(\.level), [1, 2, 3])
    }

    func test_rerouteDropsEveryPresetRouteOverride() {
        var profile = CapturePresetProfile(id: "meeting", name: "Meeting", symbolName: "person.2", postProcessingMode: .none)
        profile.captureDestinationID = UUID()
        profile.captureEntryTemplateID = UUID()
        profile.capturePlacementOverride = .prepend
        var request = CaptureRequest(
            source: .app,
            destinationID: UUID(),
            payloads: [.text("Agenda")],
            voxProfile: profile,
            relativeNotePathOverride: "Meetings/Sync.md",
            placementOverride: .prepend,
            entryTemplateIDOverride: UUID(),
            attachmentsFolderNameOverride: "Meetings/attachments"
        )
        let inboxID = UUID()

        CaptureInboxRecovery.reroute(&request, to: inboxID)

        XCTAssertEqual(request.destinationID, inboxID)
        XCTAssertNil(request.relativeNotePathOverride)
        XCTAssertNil(request.placementOverride)
        XCTAssertNil(request.entryTemplateIDOverride)
        XCTAssertNil(request.attachmentsFolderNameOverride)
        XCTAssertNil(request.voxProfile?.captureDestinationID)
        XCTAssertNil(request.voxProfile?.captureEntryTemplateID)
        XCTAssertNil(request.voxProfile?.capturePlacementOverride)
        XCTAssertEqual(request.voxProfile?.id, "meeting", "processing settings are kept")
    }

    func test_obsidianURLsEncodeVaultAndFile() throws {
        let open = try XCTUnwrap(CaptureInboxRecovery.obsidianOpenURL(
            vaultName: "My Vault",
            relativePath: "Meetings/2026-11-01.md"
        ))
        XCTAssertEqual(open.scheme, "obsidian")
        XCTAssertEqual(open.host, "open")
        let items = URLComponents(url: open, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first(where: { $0.name == "vault" })?.value, "My Vault")
        XCTAssertEqual(items?.first(where: { $0.name == "file" })?.value, "Meetings/2026-11-01")

        let search = try XCTUnwrap(CaptureInboxRecovery.obsidianSearchURL(query: "dentist appointment"))
        XCTAssertEqual(search.host, "search")
        XCTAssertEqual(
            URLComponents(url: search, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "query" })?.value,
            "dentist appointment"
        )
    }
}
