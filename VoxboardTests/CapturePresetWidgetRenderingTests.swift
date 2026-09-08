import SwiftUI
import UIKit
import VoxboardCaptureCore
import WidgetKit
import XCTest

/// Real mounted presentation, not the system's Edit Widget configuration host,
/// not touch/VoiceOver QA, and not evidence of WidgetKit refresh scheduling.
@MainActor
final class CapturePresetWidgetRenderingTests: XCTestCase {
    func testActualWidgetMountsAllFamiliesWithRTLAndLargeText() async throws {
        let profiles = (0..<8).map { index in
            CapturePresetProfile(id: "preset-\(index)", name: index == 0 ? "旅行とミーティング notes" : "Preset \(index)", symbolName: "waveform", emoji: index % 2 == 0 ? "👨🏽‍💻" : nil)
        }
        let snapshot = CapturePresetWidgetSnapshot(selection: .followCaptureBar, pins: .stored(profiles.map(\.id)), profiles: profiles)
        for family in [WidgetFamily.systemSmall, .systemMedium, .systemLarge] {
            for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                for typeSize in [DynamicTypeSize.large, .xxLarge, .xxxLarge, .accessibility3, .accessibility5] {
                    try await mount(snapshot, family: family, direction: direction, typeSize: typeSize)
                }
            }
        }
    }

    func testActualWidgetMountsEmptyDisabledDeletedAndInteriorEmptySlots() async throws {
        let profiles = [CapturePresetProfile(id: "disabled", name: "Disabled Preset", symbolName: "book", isEnabled: false)]
        let snapshots = [
            CapturePresetWidgetSnapshot(selection: .followCaptureBar, pins: .absent, profiles: nil),
            CapturePresetWidgetSnapshot(selection: .followCaptureBar, pins: .stored([]), profiles: []),
            CapturePresetWidgetSnapshot(selection: .custom(slots: [nil, "disabled", "deleted", "disabled", nil, "deleted"]), pins: .stored([]), profiles: profiles),
            CapturePresetWidgetSnapshot(selection: .custom(slots: ["deleted"]), pins: .stored([]), profiles: profiles),
        ]
        for snapshot in snapshots {
            for family in [WidgetFamily.systemSmall, .systemMedium, .systemLarge] {
                for typeSize in [DynamicTypeSize.large, .xxLarge, .accessibility3, .accessibility5] {
                    try await mount(snapshot, family: family, direction: .rightToLeft, typeSize: typeSize)
                }
            }
        }
    }

    private func mount(
        _ snapshot: CapturePresetWidgetSnapshot,
        family: WidgetFamily,
        direction: LayoutDirection,
        typeSize: DynamicTypeSize
    ) async throws {
        let size: CGSize
        switch family {
        case .systemSmall: size = CGSize(width: 170, height: 170)
        case .systemMedium: size = CGSize(width: 364, height: 170)
        default: size = CGSize(width: 364, height: 382)
        }
        let appeared = expectation(description: "Widget body appeared")
        var measured: [String: CGRect] = [:]
        let view = CapturePresetWidgetView(snapshot: snapshot, family: family)
            .onPreferenceChange(CapturePresetWidgetBounds.self) { measured = $0 }
            .padding(16)
            .frame(width: size.width, height: size.height)
            .ignoresSafeArea() // Widget content has margins, not an iOS status bar.
            .environment(\.layoutDirection, direction)
            .environment(\.dynamicTypeSize, typeSize)
            .onAppear { appeared.fulfill() }
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        defer { window.isHidden = true; window.rootViewController = nil }
        window.rootViewController = host
        window.isHidden = false
        host.loadViewIfNeeded()
        window.layoutIfNeeded()
        await fulfillment(of: [appeared], timeout: 3)
        try await Task.sleep(for: .milliseconds(100))
        host.view.layoutIfNeeded()
        // The named coordinate space is the widget content viewport, inside
        // the 16pt margins. Child labels use natural vertical sizing, so their
        // overflow cannot hide behind a merely nonzero/fixed host frame.
        let viewport = CGRect(x: 0, y: 0, width: size.width - 32, height: size.height - 32)
        XCTAssertFalse(measured.isEmpty, "No actual child geometry was delivered")
        for (name, bounds) in measured {
            XCTAssertTrue(viewport.insetBy(dx: -1, dy: -1).contains(bounds),
                          "Clipped \(name): \(bounds) outside \(viewport), \(family), \(typeSize)")
            XCTAssertGreaterThan(bounds.height, 0, "Collapsed \(name)")
        }
        if family != .systemSmall {
            let tiles = Array(snapshot.tiles.prefix(family == .systemLarge ? 8 : 6))
            for tile in tiles {
                let bounds = try XCTUnwrap(measured["\(tile.id)-tile"], "Missing fixed slot \(tile.id)")
                XCTAssertGreaterThanOrEqual(bounds.height, 44)
                for suffix in ["name", "icon", "fix"] {
                    if let child = measured["\(tile.id)-\(suffix)"] {
                        XCTAssertTrue(bounds.insetBy(dx: -1, dy: -1).contains(child), "Child escaped slot \(tile.id)")
                    }
                }
            }
            for (first, second) in zip(tiles, tiles.dropFirst()) {
                let a = try XCTUnwrap(measured["\(first.id)-tile"])
                let b = try XCTUnwrap(measured["\(second.id)-tile"])
                if abs(a.minY - b.minY) < 1 {
                    XCTAssertTrue(direction == .leftToRight ? a.maxX <= b.minX : b.maxX <= a.minX,
                                  "Fixed slots overlapped or reversed reading order")
                } else {
                    XCTAssertGreaterThanOrEqual(b.minY, a.maxY, "Rows overlapped or reordered")
                }
            }
        }
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Capture presets \(family) \(direction) \(typeSize) \(snapshot.emptyState == nil ? "tiles" : "setup")"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
