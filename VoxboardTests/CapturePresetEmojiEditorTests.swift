import Observation
import SwiftUI
import UIKit
import VoxboardShared
import XCTest
@testable import Voxboard

@MainActor
final class CapturePresetEmojiEditorTests: XCTestCase {
    func testApplyAcceptsWholeEmojiAndRetainsSymbolAndPresetFields() throws {
        let preset = samplePreset(emoji: "📔")
        for emoji in ["🇯🇵", "👍🏽", "👩🏽‍💻", "👨‍👩‍👧‍👦", "1️⃣"] {
            let input = CapturePresetEmojiEditorInput(text: " \(emoji)\n")
            let updated = try XCTUnwrap(input.applying(to: preset))
            var expected = preset
            expected.emoji = emoji
            XCTAssertEqual(updated, expected)
            XCTAssertEqual(updated.symbolName, "book")
            XCTAssertEqual(input.text, " \(emoji)\n", "Validation must not rewrite the native field")
            XCTAssertNil(input.validationMessage)
        }
    }

    func testInvalidAndEmptyInputCannotClearOrTruncatePriorEmoji() {
        let preset = samplePreset(emoji: "📔")
        for text in ["", " \n", "hello", "👩🏽‍💻📔", "1", "👍🏽\u{200D}", "🏽"] {
            let input = CapturePresetEmojiEditorInput(text: text)
            XCTAssertNil(input.applying(to: preset), text)
            XCTAssertNotNil(input.validationMessage, text)
            XCTAssertEqual(input.text, text)
            XCTAssertEqual(preset.emoji, "📔")
        }
    }

    func testChoosingSymbolClearsEmojiInOneBindingWriteAndRoundTrips() throws {
        let suite = "CapturePresetEmojiEditorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = samplePreset(emoji: "👩🏽‍💻")
        var current = original
        var writes = 0
        let binding = Binding(get: { current }, set: { updated in
            current = updated
            writes += 1
            // Isolated binding boundary: no production routes/Watch/App Group.
            do {
                defaults.set(try JSONEncoder().encode([updated]), forKey: CapturePresetStore.flowsKey)
            } catch {
                XCTFail("The real preset must encode at the binding boundary: \(error)")
            }
        })

        binding.wrappedValue = CapturePresetEmojiEditorInput.selectingSymbol("mic", for: current)
        XCTAssertEqual(writes, 1)
        var expected = original
        expected.symbolName = "mic"
        expected.emoji = nil
        XCTAssertEqual(current, expected)
        let stored = try XCTUnwrap(defaults.data(forKey: CapturePresetStore.flowsKey))
        XCTAssertEqual(try JSONDecoder().decode([CapturePreset].self, from: stored), [expected])
        let input = CapturePresetEmojiEditorInput(text: "🇯🇵")
        binding.wrappedValue = try XCTUnwrap(input.applying(to: current))
        XCTAssertEqual(writes, 2)
        XCTAssertEqual(current.symbolName, "mic")
        XCTAssertEqual(current.emoji, "🇯🇵")
        let savedEmoji = try XCTUnwrap(defaults.data(forKey: CapturePresetStore.flowsKey))
        XCTAssertEqual(try JSONDecoder().decode([CapturePreset].self, from: savedEmoji), [current])
    }

    func testUnrecognizedStoredEmojiIsPreservedUntilExplicitChoice() {
        let preset = samplePreset(emoji: "future-emoji")
        let input = CapturePresetEmojiEditorInput(text: preset.emoji!)
        XCTAssertNil(input.applying(to: preset))
        XCTAssertEqual(preset.emoji, "future-emoji")
        XCTAssertEqual(preset.symbolName, "book")
        XCTAssertEqual(FlowIconPickerView.iconName(for: " \n"), "waveform")
        XCTAssertEqual(FlowIconPickerView.iconName(for: " book "), "book")
    }

    func testNativeEmojiFieldRetainsInvalidPasteWithoutWritingPreset() async throws {
        let state = CapturePresetEmojiNativeInputState(preset: samplePreset(emoji: "📔"))
        let binding = Binding(get: { state.preset }, set: { state.preset = $0; state.writes += 1 })
        let inputBinding = Binding(get: { state.text }, set: { state.text = $0 })
        let host = UIHostingController(rootView: CapturePresetEmojiEditorForm(preset: binding, text: inputBinding))
        let window = show(host)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await settle(window)
        let field = try XCTUnwrap(textFields(in: host.view).first)
        XCTAssertEqual(field.text, "📔")
        XCTAssertEqual(field.keyboardType, .default)
        XCTAssertEqual(field.autocorrectionType, .no)

        for text in ["👩🏽‍💻📔", "👩🏽‍💻\u{200D}", "", "🇯🇵"] {
            field.text = text
            field.sendActions(for: .editingChanged)
            try await settle(window)
            XCTAssertEqual(field.text, text, "The native input must not be truncated or normalized in-place")
            XCTAssertEqual(state.text, text, "The real native editing event must reach the input binding")
            XCTAssertEqual(state.preset.emoji, "📔", "Only an explicit valid Apply may save")
            XCTAssertEqual(state.writes, 0)
        }
        attach(host.view, name: "Native emoji input, valid but unapplied")
    }

    func testIdentityAndIconPickersMountAtNarrowLargeTextAndRTL() async throws {
        let variants: [(CGFloat, DynamicTypeSize, LayoutDirection)] = [
            (320, .large, .leftToRight),
            (390, .accessibility3, .leftToRight),
            (320, .large, .rightToLeft),
        ]
        for emoji: String? in [nil, "👨‍👩‍👧‍👦", "invalid 📔📔"] {
            for (width, typeSize, direction) in variants {
                let preset = samplePreset(emoji: emoji)
                for picker in [false, true] {
                    let appeared = expectation(description: "Identity presentation mounted")
                    let content = NavigationStack {
                        Group {
                            if picker {
                                CapturePresetSettingsIconPickerView(preset: .constant(preset))
                            } else {
                                Form { CapturePresetSettingsIdentitySection(preset: .constant(preset)) }
                            }
                        }
                        .onAppear { appeared.fulfill() }
                    }
                    .environment(\.dynamicTypeSize, typeSize)
                    .environment(\.layoutDirection, direction)
                    let host = UIHostingController(rootView: content)
                    let window = show(host, width: width)
                    await fulfillment(of: [appeared], timeout: 3)
                    try await settle(window)
                    XCTAssertGreaterThan(host.view.bounds.width, 0)
                    if !picker || emoji != nil {
                        XCTAssertFalse(textFields(in: host.view).isEmpty, "The real native identity/emoji field must mount")
                    }
                    attach(host.view, name: "Identity picker=\(picker) emoji=\(emoji ?? "symbol") \(width) \(typeSize) \(direction)")
                    window.isHidden = true
                    window.rootViewController = nil
                }
            }
        }
    }

    private func samplePreset(emoji: String?) -> CapturePreset {
        CapturePreset(
            id: "journal", name: "Journal / يوميات — a longer preset name", symbolName: "book", emoji: emoji,
            isEnabled: false, staticFrontmatter: ["type": "journal"],
            captureDestinationID: UUID(), captureEntryTemplateID: UUID(), capturePlacementOverride: .prepend
        )
    }

    private func show<V: View>(_ host: UIHostingController<V>, width: CGFloat = 390) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 700))
        window.rootViewController = host
        window.isHidden = false
        host.loadViewIfNeeded()
        window.layoutIfNeeded()
        return window
    }

    private func settle(_ window: UIWindow) async throws {
        window.rootViewController?.view.setNeedsLayout()
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        window.rootViewController?.view.layoutIfNeeded()
    }

    private func textFields(in view: UIView) -> [UITextField] {
        (view as? UITextField).map { [$0] } ?? view.subviews.flatMap { textFields(in: $0) }
    }

    private func attach(_ view: UIView, name: String) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
@Observable
private final class CapturePresetEmojiNativeInputState {
    var preset: CapturePreset
    var text: String
    var writes = 0

    init(preset: CapturePreset) {
        self.preset = preset
        self.text = preset.emoji ?? ""
    }
}
