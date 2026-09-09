import Foundation
import SwiftUI
import UIKit
import VoxboardShared
import XCTest
@testable import Voxboard

@MainActor
final class CapturePresetAudioFilenameSettingsTests: XCTestCase {
    func testFieldIsHiddenWhenAudioIsOffAndWritesOnlyNormalTemplateForBothSaveModes() async throws {
        let variants: [(CapturePresetAudioSaveMode, CGFloat, DynamicTypeSize, LayoutDirection)] = [
            (.off, 320, .large, .leftToRight),
            (.alongsideTranscript, 320, .accessibility3, .rightToLeft),
            (.attachmentsFolder, 390, .accessibility2, .leftToRight),
        ]

        for (mode, width, typeSize, direction) in variants {
            var original = samplePreset(audioSaveMode: mode)
            original.audioFilenameTemplate = "initial-{id8}"
            let watchBytes = Data(original.watchRecordingSettings.filenameTemplate.utf8)
            let state = AudioFilenamePresetState(preset: original)
            let preset = Binding(
                get: { state.preset },
                set: { state.preset = $0; state.writeCount += 1 }
            )
            let appeared = expectation(description: "Audio filename settings mounted")
            let content = AnyView(
                Form {
                    Section("Voice Audio") {
                        CapturePresetAudioFilenameSettings(preset: preset)
                    }
                }
                .onAppear { appeared.fulfill() }
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.layoutDirection, direction)
            )
            let host = UIHostingController(rootView: content)
            let window = show(host, width: width)
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            await fulfillment(of: [appeared], timeout: 3)
            try await settle(window)

            let fields = textFields(in: host.view)
            if mode == .off {
                XCTAssertTrue(fields.isEmpty)
                XCTAssertEqual(state.preset, original)
                XCTAssertEqual(state.writeCount, 0)
            } else {
                let field = try XCTUnwrap(fields.first)
                XCTAssertEqual(fields.count, 1)
                XCTAssertEqual(field.text, "initial-{id8}")
                XCTAssertEqual(field.autocapitalizationType, .none)
                XCTAssertEqual(field.autocorrectionType, .no)

                let edited = "../voice-{preset}-{original}.typed"
                field.text = edited
                field.sendActions(for: .editingChanged)
                try await settle(window)

                var expected = original
                expected.audioFilenameTemplate = edited
                XCTAssertEqual(state.preset, expected)
                XCTAssertGreaterThanOrEqual(state.writeCount, 1)
                XCTAssertEqual(
                    Data(state.preset.watchRecordingSettings.filenameTemplate.utf8),
                    watchBytes,
                    "Apple Watch Recording Only naming must remain byte-for-byte independent"
                )
            }
            attach(
                host.view,
                name: "Audio filename mode=\(mode.rawValue) width=\(Int(width)) type=\(typeSize) direction=\(direction)"
            )
        }
    }

    func testHelpIdentifiersAndIntegratedRendererPreviewCoverDocumentedBehavior() throws {
        let supportedTokens = [
            "{timestamp}", "{date}", "{time}", "{YR}",
            "{id}", "{id8}", "{preset}", "{original}",
        ]
        for token in supportedTokens {
            XCTAssertTrue(CapturePresetAudioFilenameSettings.tokensHelp.contains(token))
        }
        XCTAssertTrue(CapturePresetAudioFilenameSettings.behaviorHelp.contains("Leave blank"))
        XCTAssertTrue(CapturePresetAudioFilenameSettings.behaviorHelp.contains("typed extension is ignored"))
        XCTAssertTrue(CapturePresetAudioFilenameSettings.behaviorHelp.contains("actual encoded or copied"))
        XCTAssertTrue(CapturePresetAudioFilenameSettings.behaviorHelp.contains("path-like input"))
        XCTAssertTrue(CapturePresetAudioFilenameSettings.behaviorHelp.contains("sanitized"))
        XCTAssertEqual(
            CapturePresetAudioFilenameSettings.fieldAccessibilityIdentifier,
            "capture_preset_audio_filename_template"
        )
        XCTAssertEqual(
            CapturePresetAudioFilenameSettings.helpAccessibilityIdentifier,
            "capture_preset_audio_filename_help"
        )
        XCTAssertEqual(
            CapturePresetAudioFilenameSettings.previewAccessibilityIdentifier,
            "capture_preset_audio_filename_preview"
        )

        var preset = samplePreset(audioSaveMode: .alongsideTranscript)
        preset.name = "Daily Notes"
        preset.audioFilenameTemplate = " \n "
        XCTAssertNil(CapturePresetAudioFilenameSettings.previewFilename(for: preset))

        preset.audioFilenameTemplate = "daily-{id8}.mp3"
        XCTAssertEqual(
            CapturePresetAudioFilenameSettings.previewFilename(for: preset),
            "daily-01234567.m4a",
            "The integrated renderer, not the UI, must replace a typed extension"
        )

        preset.audioFilenameTemplate = "{timestamp}-{date}-{time}-{YR}-{id}-{id8}-{preset}-{original}"
        XCTAssertEqual(
            CapturePresetAudioFilenameSettings.previewFilename(for: preset),
            "2024-01-02-030405-2024-01-02-030405-24-01234567-89ab-cdef-0123-456789abcdef-01234567-Daily-Notes-Original-Recording.m4a"
        )

        preset.audioFilenameTemplate = "../../{preset}\\{original}.typed"
        let sanitized = try XCTUnwrap(CapturePresetAudioFilenameSettings.previewFilename(for: preset))
        XCTAssertEqual(sanitized, (sanitized as NSString).lastPathComponent)
        XCTAssertFalse(sanitized.contains("/"))
        XCTAssertFalse(sanitized.contains("\\"))
        XCTAssertFalse(sanitized.contains(".."))
        XCTAssertTrue(sanitized.hasSuffix(".m4a"))
    }

    func testLegacyVoiceContextUsesDeliveredTranscriptSnapshotAndExcludesImports() throws {
        let transcriptID = try XCTUnwrap(UUID(uuidString: "ABCDEF12-3456-7890-ABCD-EF1234567890"))
        let transcriptDate = Date(timeIntervalSince1970: 1_704_164_645)
        let transcript = Transcript(
            id: transcriptID,
            text: "Stable transcript",
            date: transcriptDate,
            duration: 12,
            modelUsed: "Test",
            language: "en"
        )
        var recordingTimePreset = samplePreset(audioSaveMode: .alongsideTranscript)
        recordingTimePreset.name = "Recording-Time Name"
        recordingTimePreset.audioFilenameTemplate = "{id8}-{date}-{preset}-{original}"

        let context = try XCTUnwrap(IOSLegacyVoiceAudioDelivery.audioFilenameContext(
            transcript: transcript,
            flowSnapshot: recordingTimePreset,
            originalAudioFilename: "Original Take.wav",
            captureSource: .voice
        ))
        var currentlyEditedPreset = recordingTimePreset
        currentlyEditedPreset.name = "Edited After Recording"
        currentlyEditedPreset.audioFilenameTemplate = "different"

        XCTAssertEqual(context.identifier, transcriptID.uuidString)
        XCTAssertEqual(context.createdAt, transcriptDate)
        XCTAssertEqual(context.presetName, "Recording-Time Name")
        XCTAssertEqual(context.originalFilename, "Original Take.wav")
        XCTAssertNotEqual(context.presetName, currentlyEditedPreset.displayName)
        XCTAssertNil(IOSLegacyVoiceAudioDelivery.audioFilenameContext(
            transcript: transcript,
            flowSnapshot: recordingTimePreset,
            originalAudioFilename: "User Import.mp3",
            captureSource: .fileImport
        ))
    }

    func testLegacyVoiceDeliveryPassesContextIntoActualCheckpointedExporter() async throws {
        let fixture = try LegacyAudioFixture(noteName: "Legacy Note", sourceName: "retained-copy.wav")
        defer { fixture.cleanup() }
        let transcriptID = try XCTUnwrap(UUID(uuidString: "ABCDEF12-3456-7890-ABCD-EF1234567890"))
        let transcript = Transcript(
            id: transcriptID,
            text: "Delivered transcript",
            date: Date(timeIntervalSince1970: 1_704_164_645),
            duration: 4,
            modelUsed: "Test",
            language: "en"
        )
        var flow = samplePreset(audioSaveMode: .alongsideTranscript)
        flow.name = "Recording Preset"
        flow.audioFilenameTemplate = "voice-{id8}-{preset}-{original}.typed"
        let probe = AudioDeliveryCheckpointProbe()

        let delivered = try await IOSLegacyVoiceAudioDelivery.deliver(
            sourceAudioURL: fixture.source,
            transcriptFileURL: fixture.note,
            flowSnapshot: flow,
            transcript: transcript,
            originalAudioFilename: "First Take.final.wav",
            captureSource: .voice,
            transcriptFolderScopeURL: fixture.notes,
            checkpointExport: { probe.record($0) },
            checkpointReference: { probe.recordReference() }
        )

        let audioURL = try XCTUnwrap(delivered)
        XCTAssertEqual(
            audioURL.deletingPathExtension().lastPathComponent,
            "voice-abcdef12-Recording-Preset-First-Take.final"
        )
        XCTAssertEqual(probe.exportedURL, audioURL)
        XCTAssertEqual(probe.referenceCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testLegacyVoiceDeliveryKeepsAutomaticNamesForBlankTemplateAndImportedMedia() async throws {
        let transcript = Transcript(
            id: UUID(),
            text: "Delivered transcript",
            date: Date(timeIntervalSince1970: 1_704_164_645),
            duration: 4,
            modelUsed: "Test",
            language: "en"
        )

        var blankFlow = samplePreset(audioSaveMode: .alongsideTranscript)
        blankFlow.audioFilenameTemplate = " \n "
        let automatic = try LegacyAudioFixture(noteName: "Automatic Note", sourceName: "voice.wav")
        defer { automatic.cleanup() }
        let blankResult = try await IOSLegacyVoiceAudioDelivery.deliver(
            sourceAudioURL: automatic.source,
            transcriptFileURL: automatic.note,
            flowSnapshot: blankFlow,
            transcript: transcript,
            originalAudioFilename: "voice.wav",
            captureSource: .voice,
            checkpointExport: { _ in },
            checkpointReference: {}
        )
        XCTAssertEqual(try XCTUnwrap(blankResult).lastPathComponent, "Automatic Note.wav")

        var importedFlow = blankFlow
        importedFlow.audioFilenameTemplate = "must-not-rename-{original}"
        let imported = try LegacyAudioFixture(noteName: "Imported Note", sourceName: "user-file.wav")
        defer { imported.cleanup() }
        let importedResult = try await IOSLegacyVoiceAudioDelivery.deliver(
            sourceAudioURL: imported.source,
            transcriptFileURL: imported.note,
            flowSnapshot: importedFlow,
            transcript: transcript,
            originalAudioFilename: "Vacation Interview.wav",
            captureSource: .fileImport,
            checkpointExport: { _ in },
            checkpointReference: {}
        )
        XCTAssertEqual(try XCTUnwrap(importedResult).lastPathComponent, "Imported Note.wav")
    }

    private func samplePreset(audioSaveMode: CapturePresetAudioSaveMode) -> CapturePreset {
        var preset = CapturePreset(
            id: "daily",
            name: "Daily Notes",
            symbolName: "waveform",
            emoji: "🎙️",
            isEnabled: false,
            staticFrontmatter: ["kind": "voice"],
            locationPolicy: CapturePresetLocationPolicy(isEnabled: true, precision: .city),
            postProcessingMode: .meetingNotes,
            customPostProcessingInstruction: "Keep decisions",
            speakerDiarizationEnabled: true,
            captureProcessingEnabled: true,
            generateImageAltText: true,
            captureProcessingScope: .voiceOnly,
            capturePrompt: "Speak now",
            watchOutputMode: .recordingOnly,
            watchRecordingSettings: CapturePresetWatchRecordingSettings(
                folderBookmark: Data([0, 1, 2, 255]),
                folderName: "Watch / Folder",
                filenameTemplate: "watch/{timestamp}\u{0001}—原音.m4a"
            ),
            audioSaveMode: audioSaveMode,
            audioFilenameTemplate: "",
            attachmentsFolderName: "voice-assets",
            captureDestinationID: UUID(),
            captureEntryTemplateID: UUID(),
            capturePlacementOverride: .prepend
        )
        preset.exportSettings.embedAudioInMarkdown = true
        preset.exportSettings.audioEmbedPlacement = .top
        return preset
    }

    private func show(_ host: UIHostingController<AnyView>, width: CGFloat) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 760))
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
        XCTAssertGreaterThan(view.bounds.width, 0)
        XCTAssertGreaterThan(view.bounds.height, 0)
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private final class AudioFilenamePresetState {
    var preset: CapturePreset
    var writeCount = 0

    init(preset: CapturePreset) {
        self.preset = preset
    }
}

private struct LegacyAudioFixture {
    let root: URL
    let notes: URL
    let source: URL
    let note: URL

    init(noteName: String, sourceName: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "CapturePresetAudioFilenameSettingsTests-\(UUID().uuidString)",
            isDirectory: true
        )
        notes = root.appendingPathComponent("Notes", isDirectory: true)
        source = root.appendingPathComponent(sourceName)
        note = notes.appendingPathComponent(noteName).appendingPathExtension("md")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data("retained test audio".utf8).write(to: source, options: .atomic)
        try "Transcript".write(to: note, atomically: true, encoding: .utf8)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class AudioDeliveryCheckpointProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var _exportedURL: URL?
    private var _referenceCount = 0

    var exportedURL: URL? { lock.withLock { _exportedURL } }
    var referenceCount: Int { lock.withLock { _referenceCount } }

    func record(_ url: URL) {
        lock.withLock { _exportedURL = url }
    }

    func recordReference() {
        lock.withLock { _referenceCount += 1 }
    }
}
