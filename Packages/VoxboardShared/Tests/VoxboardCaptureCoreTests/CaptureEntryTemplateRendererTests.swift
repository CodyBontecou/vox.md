import XCTest
@testable import VoxboardCaptureCore

final class CaptureEntryTemplateRendererTests: XCTestCase {
    func test_titleTokenRendersFirstLineAndDropsTheRepeatedHeading() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let request = CaptureRequest(
            createdAt: Date(timeIntervalSince1970: 1_704_192_120), // 2024-01-02 10:42 UTC
            source: .app,
            destinationID: UUID(),
            payloads: [.text("# Project sync\n- [ ] Review final designs\n\nDecision: ship {title} literally")]
        )
        let template = "### {hour}:{minute} · {title}\n"
        let prefix = CaptureEntryTemplateRenderer(calendar: calendar).render(template, for: request)
        XCTAssertEqual(prefix, "### 10:42 · Project sync\n")

        let entry = "# Project sync\n- [ ] Review final designs\n\nDecision: ship {title} literally"
        XCTAssertEqual(
            CaptureEntryTemplateRenderer.entry(entry, under: template, for: request),
            "- [ ] Review final designs\n\nDecision: ship {title} literally"
        )
        // Without {title} in the template, or when the first line isn't a
        // heading repeating the title, the entry is unchanged.
        XCTAssertEqual(CaptureEntryTemplateRenderer.entry(entry, under: "### {hour}:{minute}\n", for: request), entry)
        XCTAssertEqual(
            CaptureEntryTemplateRenderer.entry("Book recs\nThe Overstory", droppingHeadingFor: "Book recs"),
            "Book recs\nThe Overstory"
        )
    }

    func test_titleTokenIsEmptyWithoutText() {
        let request = CaptureRequest(source: .app, destinationID: UUID(), payloads: [])
        XCTAssertEqual(CaptureEntryTemplateRenderer().render("### {title}", for: request), "### ")
    }

    func test_locationTokenSpellingAndDetectionStayAligned() {
        XCTAssertEqual(CaptureEntryTemplateRenderer.locationToken, "{location}")
        XCTAssertTrue(CaptureEntryTemplateRenderer.referencesLocation(in: "📍 {location}"))
        XCTAssertTrue(CaptureEntryTemplateRenderer.referencesLocation(in: "{date} {location} {time}"))
        XCTAssertFalse(CaptureEntryTemplateRenderer.referencesLocation(in: "{date} {time}"))
        XCTAssertFalse(CaptureEntryTemplateRenderer.referencesLocation(in: "Loc:{location-ish}"))
        XCTAssertFalse(CaptureEntryTemplateRenderer.referencesLocation(in: ""))
    }

    func test_rendersLocalDateTimeSourceAndRequestTokens() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let request = CaptureRequest(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            createdAt: Date(timeIntervalSince1970: 1_704_164_645),
            source: .shareExtension,
            destinationID: UUID(),
            payloads: [.text("Keep {date} literal in user content")]
        )

        let rendered = CaptureEntryTemplateRenderer(calendar: calendar).render(
            "captured: {date} ({YR}) {time}\nsource: {source}\nrequest: {id8}",
            for: request
        )

        XCTAssertEqual(
            rendered,
            "captured: 2024-01-02 (24) 030405\nsource: shareExtension\nrequest: aaaaaaaa"
        )
        guard case .text(let text) = request.payloads[0] else {
            return XCTFail("Expected text")
        }
        XCTAssertEqual(text, "Keep {date} literal in user content")
    }

    func test_rendersComposableHourMinuteAndSecondTokens() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let request = CaptureRequest(
            createdAt: Date(timeIntervalSince1970: 1_704_164_645),
            source: .app,
            destinationID: UUID(),
            payloads: [.text("Literal {hour}:{minute}:{second} stays untouched")]
        )

        let rendered = CaptureEntryTemplateRenderer(calendar: calendar).render(
            "{hour}:{minute}:{second} {date}",
            for: request
        )

        XCTAssertEqual(rendered, "03:04:05 2024-01-02")
        XCTAssertEqual(request.payloads, [.text("Literal {hour}:{minute}:{second} stays untouched")])
    }

    func test_rendersPrivacyAdjustedLocationMapLinkWithoutChangingPayloadText() {
        let request = CaptureRequest(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            source: .app,
            destinationID: UUID(),
            payloads: [.text("Keep {location} literal in user content")],
            voxProfile: locationProfile(precision: .exact),
            locationOutcome: .available(locationSnapshot(precision: .exact))
        )

        XCTAssertEqual(
            CaptureEntryTemplateRenderer().render("📍 {location}", for: request),
            "📍 [Location](https://www.google.com/maps/search/?api=1&query=45.501235%2C-73.567890)"
        )
        XCTAssertEqual(request.payloads, [.text("Keep {location} literal in user content")])
    }

    func test_locationTokenUsesMorePrivateCityPrecisionWhenPolicyAndSnapshotDiffer() {
        let request = CaptureRequest(
            source: .app,
            destinationID: UUID(),
            payloads: [.text("City capture")],
            voxProfile: locationProfile(precision: .city),
            locationOutcome: .available(locationSnapshot(precision: .exact))
        )

        XCTAssertEqual(
            CaptureEntryTemplateRenderer().render("{location}", for: request),
            "[Location](https://www.google.com/maps/search/?api=1&query=45.50%2C-73.57)"
        )
    }

    func test_locationTokenIsEmptyWithoutUsableOptedInLocation() {
        let unavailable = CaptureRequest(
            source: .app,
            destinationID: UUID(),
            payloads: [.text("Unavailable")],
            voxProfile: locationProfile(precision: .exact),
            locationOutcome: .unavailable(.permissionDenied, attemptedAt: Date())
        )
        let disabled = CaptureRequest(
            source: .app,
            destinationID: UUID(),
            payloads: [.text("Disabled")],
            voxProfile: CapturePresetProfile(id: "disabled", name: "Disabled", symbolName: "location"),
            locationOutcome: .available(locationSnapshot(precision: .exact))
        )
        let malformed = CaptureRequest(
            source: .app,
            destinationID: UUID(),
            payloads: [.text("Malformed")],
            voxProfile: locationProfile(precision: .exact),
            locationOutcome: .available(CaptureLocationSnapshot(
                latitude: .infinity,
                longitude: 0,
                timestamp: Date(),
                source: .app,
                precision: .exact
            ))
        )

        for request in [unavailable, disabled, malformed] {
            XCTAssertEqual(
                CaptureEntryTemplateRenderer().render("before{location}after", for: request),
                "beforeafter"
            )
        }
    }

    func test_unknownTokensArePreservedForForwardCompatibility() {
        let request = CaptureRequest(source: .app, destinationID: UUID(), payloads: [.text("Hi")])

        XCTAssertEqual(
            CaptureEntryTemplateRenderer().render("before {unknown} after", for: request),
            "before {unknown} after"
        )
    }

    private func locationProfile(precision: CaptureLocationPrecision) -> CapturePresetProfile {
        CapturePresetProfile(
            id: "location",
            name: "Location",
            symbolName: "location",
            locationPolicy: CapturePresetLocationPolicy(isEnabled: true, precision: precision)
        )
    }

    private func locationSnapshot(precision: CaptureLocationPrecision) -> CaptureLocationSnapshot {
        CaptureLocationSnapshot(
            latitude: 45.50123456,
            longitude: -73.56789,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            source: .app,
            precision: precision
        )
    }
}
