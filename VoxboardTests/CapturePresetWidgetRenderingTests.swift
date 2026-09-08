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
                for typeSize in [DynamicTypeSize.large, .accessibility3] {
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
            CapturePresetWidgetSnapshot(selection: .custom(slots: [nil, "disabled", "deleted"]), pins: .stored([]), profiles: profiles),
        ]
        for snapshot in snapshots {
            for family in [WidgetFamily.systemSmall, .systemMedium, .systemLarge] {
                try await mount(snapshot, family: family, direction: .rightToLeft, typeSize: .large)
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
        let view = CapturePresetWidgetView(snapshot: snapshot, family: family)
            .padding(16)
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
        XCTAssertGreaterThan(host.view.bounds.width, 0)
        XCTAssertGreaterThan(host.view.bounds.height, 0)
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Capture presets \(family) \(direction) \(typeSize) \(snapshot.emptyState == nil ? "tiles" : "setup")"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
