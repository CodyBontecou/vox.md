import XCTest
@testable import VoxboardShared

final class TranscriptPropertyMappingTests: XCTestCase {
    private func transcript(_ text: String) -> Transcript {
        Transcript(text: text, duration: 2, modelUsed: "base", language: "en")
    }

    func testLegacyPresetKeepsBodyAndMappingSurvivesRoundTrip() throws {
        var preset = CapturePresetStore.makeCustomFlow()
        let legacy = Data("{\"id\":\"custom\",\"name\":\"Task\"}".utf8)
        let decoded = try JSONDecoder().decode(CapturePreset.self, from: legacy)
        XCTAssertEqual(decoded.transcriptPropertyName, "")
        XCTAssertTrue(decoded.includeTranscriptInBody)
        preset.transcriptPropertyName = "note"
        preset.includeTranscriptInBody = false
        XCTAssertEqual(try JSONDecoder().decode(CapturePreset.self, from: JSONEncoder().encode(preset)), preset)
    }

    func testInvalidOrEmptyKeysNeverSuppressBody() throws {
        var preset = CapturePresetStore.makeCustomFlow()
        preset.includeTranscriptInBody = false
        for key in ["", " ", "note: injected", "note\nother", "[note]"] {
            preset.transcriptPropertyName = key
            XCTAssertEqual(TranscriptCaptureAdapter.payloads(transcript: transcript("spoken words"), flow: preset, audioAsset: nil), [.text("spoken words")])
        }
        XCTAssertEqual(TranscriptPropertyMapping.normalizedKey(" note "), "note")
        XCTAssertEqual(TranscriptPropertyMapping.normalizedKey("task-description"), "task-description")
    }

    func testMappingUsesCleanedTextAndWinsOverStaticMetadata() throws {
        var preset = CapturePresetStore.makeCustomFlow()
        preset.transcriptPropertyName = "note"
        preset.staticFrontmatter = ["note": "placeholder"]
        let enriched = transcript("raw text").withEnrichment(title: nil, tags: nil, category: nil, cleanedText: "Clean text")
        let payloads = TranscriptCaptureAdapter.payloads(transcript: enriched, flow: preset, audioAsset: nil)
        XCTAssertEqual(payloads, [.text("Clean text")])
        let destination = CaptureDestination(name: "Task", rootBookmark: Data(), rootName: "Vault", noteTarget: .existingNote(relativePath: "Task.md"))
        let request = CaptureRequest(source: .voice, destinationID: destination.id, payloads: payloads, voxProfile: preset.captureProfile)
        XCTAssertEqual(try CaptureMarkdownRenderer().render(request, for: destination), "---\nnote: \"Clean text\"\n---\n\nClean text")
        XCTAssertNil(TranscriptCaptureAdapter.frontmatter(transcript: enriched, flow: preset)["note"])
    }

    func testMarkdownExportsKeepMappedTextAsAStringAndCanOmitBody() throws {
        for text in ["true", "123", "[one, two]", "Task: \"review\" #project\nNext line\twith \\ path", "emoji 📝"] {
            for includeBody in [true, false] {
                let config = TranscriptExportConfiguration(format: .md, mode: .newFile, transcriptPropertyName: "note", includeTranscriptInBody: includeBody)
                let result = try TranscriptFileExporter.exportKitRenderedContent(transcript(text), configuration: config)
                let value = try XCTUnwrap(result.components(separatedBy: "\n").first(where: { $0.hasPrefix("note: ") })).dropFirst(6)
                XCTAssertEqual(try JSONDecoder().decode(String.self, from: Data(value.utf8)), text)
                let body = result.components(separatedBy: "---").dropFirst(2).joined(separator: "---")
                XCTAssertEqual(body.contains(text), includeBody)
            }
        }
    }

    func testTypedCapturesKeepBodyAndAudioTranscriptsKeepAttachment() throws {
        var preset = CapturePresetStore.makeCustomFlow()
        preset.transcriptPropertyName = "note"
        preset.includeTranscriptInBody = false
        let destination = CaptureDestination(name: "Task", rootBookmark: Data(), rootName: "Vault", noteTarget: .existingNote(relativePath: "Task.md"))
        let typed = CaptureRequest(source: .app, destinationID: destination.id, payloads: [.text("typed words")], voxProfile: preset.captureProfile)
        XCTAssertEqual(try CaptureMarkdownRenderer().render(typed, for: destination), "typed words")
        let asset = try CaptureAssetReference(relativePath: "recording.wav", originalFilename: "recording.wav", contentTypeIdentifier: "public.wav", byteCount: 4)
        let voice = CaptureRequest(source: .voice, destinationID: destination.id, payloads: [.audio(asset, transcript: "spoken words")], voxProfile: preset.captureProfile)
        let rendered = try CaptureMarkdownRenderer().render(voice, for: destination)
        XCTAssertTrue(rendered.contains("note: \"spoken words\""))
        XCTAssertTrue(rendered.contains("![["))
        XCTAssertEqual(rendered.components(separatedBy: "spoken words").count, 2)
    }

    func testTemplatePropertyOnlyPreservesTemplateBody() throws {
        let config = TranscriptExportConfiguration(format: .md, mode: .newFile, transcriptPropertyName: "note", includeTranscriptInBody: false, markdownTemplateContent: "---\nnote: placeholder\nstatus: open\n---\n\n## Workflow")
        let result = try TranscriptFileExporter.exportKitRenderedContent(transcript("spoken description"), configuration: config)
        XCTAssertTrue(result.contains("note: \"spoken description\""))
        XCTAssertTrue(result.contains("## Workflow"))
        XCTAssertFalse(result.contains("placeholder"))
        XCTAssertEqual(result.components(separatedBy: "spoken description").count, 2)
    }

    func testDestinationPropertyOnlyReplacesExistingValueAndKeepsBody() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let note = root.appendingPathComponent("Task.md")
        try "---\nnote: old description\nstatus: open\n---\n\n## Workflow\nExisting body".write(to: note, atomically: true, encoding: .utf8)
        let destination = CaptureDestination(name: "Task", rootBookmark: Data(), rootName: "Vault", noteTarget: .existingNote(relativePath: "Task.md"), placement: .append, entryPrefix: "- [ ] ", entrySuffix: " #task")
        var preset = CapturePresetStore.makeCustomFlow()
        preset.transcriptPropertyName = "note"
        preset.includeTranscriptInBody = false
        preset.staticFrontmatter = ["note": "static placeholder"]
        let text = "Task: \"review\"\nNext line"
        _ = try await TranscriptCaptureDestinationExporter().export(transcript: transcript(text), flow: preset, destination: destination, destinationRootURL: root, stagingDirectoryURL: root.appendingPathComponent("staging"), audioSourceURL: nil, locationOutcome: nil)
        let result = try String(contentsOf: note, encoding: .utf8)
        XCTAssertTrue(result.contains("note: \(TranscriptPropertyMapping.yamlString(text))"))
        XCTAssertFalse(result.contains("old description"))
        XCTAssertFalse(result.contains("static placeholder"))
        XCTAssertTrue(result.contains("Existing body"))
        XCTAssertFalse(result.contains("- [ ]"))
        XCTAssertFalse(result.contains("#task"))
        XCTAssertEqual(result.components(separatedBy: "review").count, 2)
    }
}
