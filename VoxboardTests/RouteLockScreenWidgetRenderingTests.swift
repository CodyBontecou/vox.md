import SwiftUI
import UIKit
import WidgetKit
import XCTest

/// Renders the real Lock Screen accessory views (Speak, Today, Scan) at
/// iPhone accessory sizes so they can be compared with the LockScreen board.
/// The simulator can't add Lock Screen widgets without the system editor.
/// Set `TEST_RUNNER_VOX_SNAPSHOT_DIR` to also write PNGs to that folder.
@MainActor
final class RouteLockScreenWidgetRenderingTests: XCTestCase {
    func testAccessoryWidgetsRenderAtLockScreenSizes() async throws {
        let today = RouteAccessoryEntry.placeholder(
            name: "Tasks",
            today: .init(latestTitle: "Book flights for Lisbon", count: 3)
        )
        let empty = RouteAccessoryEntry.placeholder(name: "Journal", today: .init(latestTitle: nil, count: 0))
        let circle = CGSize(width: 72, height: 72)
        let rectangle = CGSize(width: 172, height: 72)
        try await render("lock-speak-inbox", size: circle) {
            RouteSpeakAccessoryView(entry: .placeholder(name: "Inbox"))
        }
        try await render("lock-today-tasks", size: rectangle) {
            RouteTodayAccessoryView(entry: today)
        }
        try await render("lock-today-empty", size: rectangle) {
            RouteTodayAccessoryView(entry: empty)
        }
        try await render("lock-scan", size: circle) {
            RouteScanAccessoryView(entry: .placeholder(name: "Inbox"))
        }
    }

    private func render<Content: View>(
        _ name: String,
        size: CGSize,
        @ViewBuilder content: () -> Content
    ) async throws {
        // A dark, Lock Screen–like backdrop with white vibrant-style content.
        let view = content()
            .frame(width: size.width, height: size.height)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .padding(12)
            .background(Color(white: 0.17))
        let host = UIHostingController(rootView: view.ignoresSafeArea())
        host.safeAreaRegions = []
        host.overrideUserInterfaceStyle = .dark
        let frame = CGRect(x: 0, y: 0, width: size.width + 24, height: size.height + 24)
        let window = UIWindow(frame: frame)
        defer { window.isHidden = true; window.rootViewController = nil }
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = frame
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(image.size.width, 0)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["VOX_SNAPSHOT_DIR"],
           let data = image.pngData() {
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }
}

/// Test-only stand-in: the widget's record provider lives in a file the test
/// target doesn't compile. Rendering never builds a record URL.
enum VoxboardWidgetProvider {
    static func readQuickRecordEnabled() -> Bool { false }
}
