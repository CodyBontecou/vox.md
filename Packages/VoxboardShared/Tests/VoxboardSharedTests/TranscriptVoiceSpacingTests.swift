import XCTest
@testable import VoxboardShared

/// Byte-level coverage of the voice delivery seam, not just intermediate strings.
final class TranscriptVoiceSpacingTests: XCTestCase {
    func test_voiceBoundaryCleanupPreservesIndentationHardBreaksAndInternalBlankLines() async throws {
        for newline in ["\n", "\r\n", "\r"] {
            let fixture = try await Fixture(document: "  - [x] Older  \n \t\n  - [x] Oldest  ")
            defer { fixture.remove() }

            _ = try await fixture.export(
                [" \t", "  - [ ] First  ", " \t", "  - [ ] Second  ", "\t "].joined(separator: newline)
            )

            XCTAssertEqual(
                try fixture.bytes(),
                Data("  - [ ] First  \n \t\n  - [ ] Second  \n  - [x] Older  \n \t\n  - [x] Oldest  ".utf8)
            )
        }
    }

    func test_voiceBoundaryCleanupPreservesIndentedCode() async throws {
        let fixture = try await Fixture(document: "Older paragraph.")
        defer { fixture.remove() }

        _ = try await fixture.export(" \n    code  \n\t ")

        XCTAssertEqual(try fixture.bytes(), Data("    code  \n\nOlder paragraph.".utf8))
    }

    func test_voiceWhitespaceOnlyBoundaryLinesDoNotSeparateTaskFromPrefixOrSuffix() async throws {
        for newline in ["\n", "\r\n", "\r"] {
            for usesCleanedText in [false, true] {
                let fixture = try await Fixture(
                    document: "- [x] Older",
                    prefix: "- [ ] ",
                    suffix: " #inbox"
                )
                defer { fixture.remove() }
                let body = " \t" + newline + "Buy milk" + newline + "\t "

                _ = try await fixture.export(
                    usesCleanedText ? "Raw words not chosen" : body,
                    cleanedText: usesCleanedText ? body : nil
                )

                XCTAssertEqual(try fixture.bytes(), Data("- [ ] Buy milk #inbox\n- [x] Older".utf8))
            }
        }
    }

    func test_configuredVoicePrependKeepsPrefixAndSuffixTaskBoundariesCompact() async throws {
        let fixture = try await Fixture(
            document: "---\ntitle: Tasks\n---\n\n- [x] Older task",
            prefix: "- [ ] ",
            suffix: " #inbox"
        )
        defer { fixture.remove() }

        _ = try await fixture.export("Buy milk")

        XCTAssertEqual(
            try fixture.bytes(),
            Data("---\ntitle: Tasks\n---\n- [ ] Buy milk #inbox\n- [x] Older task".utf8)
        )
    }

    func test_successiveVoiceAndTypedEntriesHaveIdenticalCompactFileBytes() async throws {
        let shapes: [(prefix: String, older: String, prepends: [String], appends: [String])] = [
            (
                "- ", "- Older #inbox",
                ["- First #inbox\n- Older #inbox", "- Second #inbox\n- First #inbox\n- Older #inbox"],
                ["- Older #inbox\n- First #inbox", "- Older #inbox\n- First #inbox\n- Second #inbox"]
            ),
            (
                "- [ ] ", "- [x] Older #inbox",
                ["- [ ] First #inbox\n- [x] Older #inbox", "- [ ] Second #inbox\n- [ ] First #inbox\n- [x] Older #inbox"],
                ["- [x] Older #inbox\n- [ ] First #inbox", "- [x] Older #inbox\n- [ ] First #inbox\n- [ ] Second #inbox"]
            ),
        ]
        for shape in shapes {
            for placement in [CapturePlacement.prepend, .append] {
                for newline in ["\n", "\r\n", "\r"] {
                    for usesCleanedText in [false, true] {
                        let fixture = try await Fixture(
                            document: newline + shape.older + newline + newline,
                            prefix: shape.prefix,
                            suffix: " #inbox",
                            placement: placement
                        )
                        defer { fixture.remove() }
                        let typedNote = fixture.vault.appendingPathComponent("Typed.md")
                        try (newline + shape.older + newline + newline).write(
                            to: typedNote, atomically: true, encoding: .utf8
                        )
                        var typedDestination = fixture.destination
                        typedDestination.noteTarget = .existingNote(relativePath: "Typed.md")
                        let expected = placement == .prepend ? shape.prepends : shape.appends

                        for (index, text) in ["First", "Second"].enumerated() {
                            let body = newline + text + newline + newline
                            _ = try await fixture.export(
                                usesCleanedText ? "Raw words not chosen" : body,
                                cleanedText: usesCleanedText ? body : nil
                            )
                            let typed = try CaptureDraft(text: body).makeRequest(
                                source: .keyboard,
                                resolvedDestinationID: typedDestination.id,
                                voxProfile: fixture.flow.captureProfile
                            )
                            _ = try await fixture.pipeline.capture(
                                typed, destination: typedDestination, rootURL: fixture.vault
                            )
                            XCTAssertEqual(try fixture.bytes(), Data(expected[index].utf8))
                            XCTAssertEqual(try fixture.bytes(), try Data(contentsOf: typedNote))
                        }
                    }
                }
            }
        }
    }

    func test_voiceProseKeepsParagraphSpacingAndLiteralPayloadTokens() async throws {
        let fixture = try await Fixture(
            document: "Older first.\n\nOlder second.",
            prefix: "Voice: ",
            suffix: "\n\nEnd of entry."
        )
        defer { fixture.remove() }

        _ = try await fixture.export("\nFirst {date}.\n\nSecond <% crypto.randomUUID() %>.\n")

        XCTAssertEqual(
            try fixture.bytes(),
            Data("Voice: First {date}.\n\nSecond <% crypto.randomUUID() %>.\n\nEnd of entry.\n\nOlder first.\n\nOlder second.".utf8)
        )
    }

    func test_voiceEntryFormattingRendersTokensWithoutAddingBlankLines() async throws {
        let fixture = try await Fixture(
            document: "- Older",
            prefix: "- {hour}:{minute} {source}: ",
            suffix: " #inbox"
        )
        defer { fixture.remove() }

        _ = try await fixture.export("Keep {date} literal")

        XCTAssertEqual(
            try fixture.bytes(),
            Data("- 03:04 voice: Keep {date} literal #inbox\n- Older".utf8)
        )
    }

    func test_voicePreservesInternalTemplateAndListNewlines() async throws {
        let fixture = try await Fixture(
            document: "- Older\n\n- Oldest",
            prefix: "- {source}\n\n",
            suffix: "\n\nAfter {source}  "
        )
        defer { fixture.remove() }

        _ = try await fixture.export("Spoken {date}")

        XCTAssertEqual(
            try fixture.bytes(),
            Data("- voice\n\nSpoken {date}\n\nAfter voice  \n\n- Older\n\n- Oldest".utf8)
        )
    }

    func test_voiceListInsertionUnderHeadingPreservesOtherSections() async throws {
        let fixture = try await Fixture(
            document: "# Daily\n\n## Notes\n\n- Older\n\n## Journal\n\nKeep this paragraph.",
            prefix: "- ",
            placement: .beneathHeading(
                .init(title: "Notes", level: 2),
                missingHeadingBehavior: .fail,
                headingPosition: .top
            )
        )
        defer { fixture.remove() }

        _ = try await fixture.export("New\n\n- Another")

        XCTAssertEqual(
            try fixture.bytes(),
            Data("# Daily\n\n## Notes\n- New\n\n- Another\n- Older\n\n## Journal\n\nKeep this paragraph.".utf8)
        )
    }

    func test_emptyCleanedTextFallsBackToRawVoiceBodyInEmptyNote() async throws {
        let fixture = try await Fixture(document: "\r\n\r\n", prefix: "- ")
        defer { fixture.remove() }

        _ = try await fixture.export("\r\nFirst\r\n", cleanedText: "")

        XCTAssertEqual(try fixture.bytes(), Data("- First".utf8))
    }

    func test_plainVoiceEntriesRetainParagraphSeparatorsWithoutBoundaryBlankLines() async throws {
        for placement in [CapturePlacement.prepend, .append] {
            let fixture = try await Fixture(document: "\nOlder\n", placement: placement)
            defer { fixture.remove() }

            _ = try await fixture.export("\r\nFirst\r\n\r\n")

            let expected = placement == .prepend ? "First\n\nOlder" : "Older\n\nFirst"
            XCTAssertEqual(try fixture.bytes(), Data(expected.utf8))
        }
    }

    func test_emptyVoiceBodyDoesNotChangeExistingFileBytes() async throws {
        for body in ["", "\n\r\n", " \t\r\n \t"] {
            let fixture = try await Fixture(document: "User paragraph.\n\n- Older", prefix: "- ")
            defer { fixture.remove() }

            do {
                _ = try await fixture.export(body)
                XCTFail("Expected an empty capture to be rejected before writing")
            } catch ConfiguredTranscriptCaptureError.queuedForRetry(let message) {
                XCTAssertEqual(message, CaptureRenderingError.emptyRequest.localizedDescription)
            }

            XCTAssertEqual(try fixture.bytes(), Data("User paragraph.\n\n- Older".utf8))
        }
    }

    func test_voiceTodoFormattingUsesCompactWriterWithoutAnEntryPrefix() async throws {
        let fixture = try await Fixture(document: "- [x] Older", mode: .todoList)
        defer { fixture.remove() }

        _ = try await fixture.export("buy milk.")
        _ = try await fixture.export("call Sam.")

        XCTAssertEqual(try fixture.bytes(), Data("- [ ] Call Sam\n- [ ] Buy milk\n- [x] Older".utf8))
    }

    // The reporter previously described a Task preset, scratchpad prepend,
    // Watch/widget delivery, and a " Loc:{location}" suffix. The coordinates
    // and remaining settings here are synthetic, not a recovered failing preset.
    func test_reportedTaskRoutesKeepLocationSuffixCompact() async throws {
        let date = Date(timeIntervalSince1970: 1_704_164_645)
        for source in [CaptureSource.voice, .watch, .widget] {
            for hasLocation in [false, true] {
                for usesCleanedText in [false, true] {
                    let fixture = try await Fixture(
                        document: "- [x] Older",
                        suffix: " Loc:{location}",
                        mode: .todoList,
                        locationPolicy: CapturePresetLocationPolicy(
                            isEnabled: true,
                            metadataOutputEnabled: false,
                            unavailableBehavior: .sendWithoutLocation
                        )
                    )
                    defer { fixture.remove() }
                    let outcome: CaptureLocationOutcome = hasLocation
                        ? .available(CaptureLocationSnapshot(
                            latitude: 12.345678,
                            longitude: -98.765432,
                            timestamp: date,
                            source: source,
                            precision: .exact
                        ))
                        : .unavailable(.permissionDenied, attemptedAt: date)
                    let location = hasLocation
                        ? "[Location](https://www.google.com/maps/search/?api=1&query=12.345678%2C-98.765432)"
                        : ""
                    var expected = "- [x] Older"

                    for text in ["Buy milk", "Call Sam"] {
                        _ = try await fixture.export(
                            usesCleanedText ? "Raw words not chosen" : text,
                            cleanedText: usesCleanedText ? text : nil,
                            source: source,
                            locationOutcome: outcome
                        )
                        expected = "- [ ] \(text) Loc:\(location)\n" + expected
                        XCTAssertEqual(try fixture.bytes(), Data(expected.utf8))
                    }
                }
            }
        }
    }

    func test_reportedTaskRoutesKeepRawProseWhenChecklistProcessingIsOff() async throws {
        for source in [CaptureSource.voice, .watch, .widget] {
            let fixture = try await Fixture(document: "- [x] Older", mode: .none)
            defer { fixture.remove() }

            _ = try await fixture.export("Buy milk", source: source)

            // The reporter said disabling processing produced notes, not tasks.
            // Raw prose still requires a paragraph boundary beside a checklist.
            XCTAssertEqual(try fixture.bytes(), Data("Buy milk\n\n- [x] Older".utf8))
        }
    }

    func test_voiceRetryMarkersDoNotSplitPrefixFormattedLists() async throws {
        for placement in [CapturePlacement.prepend, .append] {
            let fixture = try await Fixture(
                document: "- [x] Older",
                prefix: "- [ ] ",
                placement: placement,
                retryProtection: true
            )
            defer { fixture.remove() }

            let receipt = try await fixture.export("New")

            let marker = CaptureRequestMarker.text(for: receipt.requestID)
            let expected = placement == .prepend
                ? "- [ ] New \(marker)\n- [x] Older"
                : "- [x] Older\n- [ ] New \(marker)"
            XCTAssertEqual(try fixture.bytes(), Data(expected.utf8))
        }
    }

    private struct Fixture {
        let root: URL
        let captureRoot: URL
        let vault: URL
        let note: URL
        let destination: CaptureDestination
        let flow: CapturePreset
        let pipeline: CapturePipeline

        init(
            document: String,
            prefix: String = "",
            suffix: String = "",
            placement: CapturePlacement = .prepend,
            mode: CapturePresetProcessingMode = .none,
            retryProtection: Bool = false,
            locationPolicy: CapturePresetLocationPolicy = CapturePresetLocationPolicy()
        ) async throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("voice-spacing.\(UUID().uuidString)", isDirectory: true)
            captureRoot = root.appendingPathComponent("capture", isDirectory: true)
            vault = root.appendingPathComponent("vault", isDirectory: true)
            note = vault.appendingPathComponent("Notes.md")
            try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
            try document.write(to: note, atomically: true, encoding: .utf8)
            destination = CaptureDestination(
                name: "Notes",
                rootBookmark: try vault.bookmarkData(),
                rootName: "Synthetic vault",
                noteTarget: .existingNote(relativePath: "Notes.md"),
                placement: placement,
                entryPrefix: prefix,
                entrySuffix: suffix,
                retryProtectionEnabled: retryProtection
            )
            try await CaptureLibraryStore(
                fileURL: captureRoot.appendingPathComponent(CaptureLibraryStore.defaultFilename),
                coordinator: ProcessLocalCaptureFileCoordinator.shared
            ).save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))
            var preset = CapturePresetStore.makeCustomFlow()
            preset.captureDestinationID = destination.id
            preset.postProcessingMode = mode
            preset.locationPolicy = locationPolicy
            flow = preset
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "en_US_POSIX")
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            pipeline = CapturePipeline(
                pathPlanner: CapturePathPlanner(calendar: calendar),
                writer: CoordinatedCaptureWriter(coordinator: ProcessLocalCaptureFileCoordinator.shared)
            )
        }

        func export(
            _ text: String,
            cleanedText: String? = nil,
            source: CaptureSource = .voice,
            locationOutcome: CaptureLocationOutcome? = nil
        ) async throws -> CaptureReceipt {
            try await ConfiguredTranscriptCaptureDestinationExporter.export(
                transcript: TranscriptFlowFormatter.apply(
                    flow: flow,
                    to: Transcript(
                        id: UUID(),
                        text: text,
                        date: Date(timeIntervalSince1970: 1_704_164_645),
                        duration: 1,
                        modelUsed: "synthetic",
                        language: "en",
                        cleanedText: cleanedText
                    )
                ),
                flow: flow,
                destinationID: destination.id,
                audioSourceURL: nil,
                locationOutcome: locationOutcome,
                source: source,
                captureRootURL: captureRoot,
                pipeline: pipeline
            )
        }

        func bytes() throws -> Data { try Data(contentsOf: note) }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
