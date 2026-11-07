import XCTest
@testable import VoxboardCaptureCore

final class CapturePathPlannerTests: XCTestCase {
    private let destinationID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let requestID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let date = Date(timeIntervalSince1970: 1_704_164_645) // 2024-01-02T03:04:05Z

    func test_newNote_generatesUniqueMarkdownPath() throws {
        let destination = makeDestination(target: .newNote(pathTemplate: "Inbox/{date}-{id8}.md"))
        let request = makeRequest()
        let existing = Set(["Inbox/2024-01-02-aaaaaaaa.md"])

        let path = try planner().relativePath(
            for: request,
            destination: destination,
            existingRelativePaths: existing
        )

        XCTAssertEqual(path, "Inbox/2024-01-02-aaaaaaaa-2.md")
    }

    func test_twoDigitYearTokenSupportsDayMonthYearFilenames() throws {
        let destination = makeDestination(
            target: .rollingNote(pathTemplate: "Daily/{day}-{month}-{YR}.md", period: .daily)
        )

        let path = try planner().relativePath(for: makeRequest(), destination: destination)

        XCTAssertEqual(path, "Daily/02-01-24.md")
    }

    func test_rollingDailyNote_isStableWithinDay() throws {
        let destination = makeDestination(target: .rollingNote(pathTemplate: "Daily/{date}.md", period: .daily))
        let morning = makeRequest(date: date)
        let evening = makeRequest(date: date.addingTimeInterval(60 * 60 * 18))

        XCTAssertEqual(
            try planner().relativePath(for: morning, destination: destination),
            try planner().relativePath(for: evening, destination: destination)
        )
        XCTAssertEqual(
            try planner().relativePath(for: morning, destination: destination),
            "Daily/2024-01-02.md"
        )
    }

    func test_rollingPeriodTokenUsesSelectedDailyWeeklyMonthlyQuarterlyAndYearlyBuckets() throws {
        let request = makeRequest()
        let expectations: [(CaptureRollingPeriod, String)] = [
            (.daily, "Rolling/2024-01-02.md"),
            (.weekly, "Rolling/2024-W01.md"),
            (.monthly, "Rolling/2024-01.md"),
            (.quarterly, "Rolling/2024-Q1.md"),
            (.yearly, "Rolling/2024.md"),
        ]

        for (period, expected) in expectations {
            let destination = makeDestination(
                target: .rollingNote(pathTemplate: "Rolling/{period}.md", period: period)
            )
            XCTAssertEqual(
                try planner().relativePath(for: request, destination: destination),
                expected
            )
        }
    }

    func test_rollingPeriodChangesAcrossEverySelectedBoundary() throws {
        let planner = planner()
        let calendar = planner.calendar
        let date = { (year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) in
            calendar.date(from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second
            ))!
        }
        let weeklyStart = try XCTUnwrap(
            calendar.dateInterval(of: .weekOfYear, for: date(2024, 1, 10, 12, 0, 0))?.start
        )
        let boundaries: [(CaptureRollingPeriod, Date, Date)] = [
            (.daily, date(2024, 1, 1, 23, 59, 59), date(2024, 1, 2, 0, 0, 0)),
            (.weekly, weeklyStart.addingTimeInterval(-1), weeklyStart),
            (.monthly, date(2024, 1, 31, 23, 59, 59), date(2024, 2, 1, 0, 0, 0)),
            (.quarterly, date(2024, 3, 31, 23, 59, 59), date(2024, 4, 1, 0, 0, 0)),
            (.yearly, date(2024, 12, 31, 23, 59, 59), date(2025, 1, 1, 0, 0, 0)),
        ]

        for (period, before, after) in boundaries {
            let destination = makeDestination(
                target: .rollingNote(pathTemplate: "Rolling/{period}.md", period: period)
            )
            let beforePath = try planner.relativePath(for: makeRequest(date: before), destination: destination)
            let afterPath = try planner.relativePath(for: makeRequest(date: after), destination: destination)
            XCTAssertNotEqual(beforePath, afterPath, "Expected \(period) period to change at its boundary")
        }
    }

    func test_hourMinuteAndSecondTokensRenderAsPathSafeComponents() throws {
        let destination = makeDestination(
            target: .newNote(pathTemplate: "Inbox/{hour}-{minute}-{second}-{date}.md")
        )

        let path = try planner().relativePath(for: makeRequest(), destination: destination)

        XCTAssertEqual(path, "Inbox/03-04-05-2024-01-02.md")
    }

    func test_rollingNote_respectsInjectedCalendarAndTimeZone() throws {
        let destination = makeDestination(
            target: .rollingNote(pathTemplate: "Journal/{year}/{month}/{date}.md", period: .daily)
        )
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.locale = Locale(identifier: "en_US_POSIX")
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let path = try CapturePathPlanner(calendar: losAngeles).relativePath(
            for: makeRequest(date: Date(timeIntervalSince1970: 1_704_074_645)), // 2024-01-01T02:04:05Z
            destination: destination
        )

        XCTAssertEqual(path, "Journal/2023/12/2023-12-31.md")
    }

    func test_dateTokensUseGregorianYearsWhateverTheDeviceCalendar() throws {
        let destination = makeDestination(
            target: .rollingNote(pathTemplate: "Journal/{date}/{week}/{YR}.md", period: .daily)
        )
        // 2026-11-07T12:00:00Z — Hijri 1448, Buddhist 2569, Japanese Reiwa 8.
        let request = makeRequest(date: Date(timeIntervalSince1970: 1_794_052_800))

        for identifier in [Calendar.Identifier.islamicUmmAlQura, .buddhist, .japanese, .persian, .hebrew] {
            var calendar = Calendar(identifier: identifier)
            calendar.locale = Locale(identifier: "en_US_POSIX")
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            calendar.firstWeekday = 2
            calendar.minimumDaysInFirstWeek = 4

            let path = try CapturePathPlanner(calendar: calendar).relativePath(for: request, destination: destination)

            XCTAssertEqual(path, "Journal/2026-11-07/2026-W45/26.md", "\(identifier)")
        }
    }

    func test_entryTemplateDateTokensUseGregorianYearsUnderHijriCalendar() {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.locale = Locale(identifier: "ar_SA")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let rendered = CaptureEntryTemplateRenderer(calendar: calendar).render(
            "{date} {year}-{month}-{day}",
            for: makeRequest(date: Date(timeIntervalSince1970: 1_794_052_800))
        )

        XCTAssertEqual(rendered, "2026-11-07 2026-11-07")
    }

    func test_existingNote_usesResolvedFileReference() throws {
        let destination = makeDestination(target: .existingNote(relativePath: "Projects/Vox.md"))

        XCTAssertEqual(
            try planner().relativePath(for: makeRequest(), destination: destination),
            "Projects/Vox.md"
        )
    }

    func test_plannerRejectsAbsoluteAndTraversalTemplates() {
        for template in ["/private/{date}.md", "Daily/../Secrets.md", "~/Notes.md"] {
            let destination = makeDestination(target: .newNote(pathTemplate: template))

            XCTAssertThrowsError(try planner().relativePath(for: makeRequest(), destination: destination))
        }
    }

    private func planner() -> CapturePathPlanner {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return CapturePathPlanner(calendar: calendar)
    }

    private func makeRequest(date: Date? = nil) -> CaptureRequest {
        CaptureRequest(
            id: requestID,
            createdAt: date ?? self.date,
            source: .app,
            destinationID: destinationID,
            payloads: [.text("hello")]
        )
    }

    private func makeDestination(target: CaptureNoteTarget) -> CaptureDestination {
        CaptureDestination(
            id: destinationID,
            name: "Test",
            rootBookmark: Data([1, 2, 3]),
            rootName: "Vault",
            noteTarget: target
        )
    }
}

final class CapturePathPlannerTitleTokenTests: XCTestCase {
    private let destinationID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let requestID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let date = Date(timeIntervalSince1970: 1_704_164_645) // 2024-01-02T03:04:05Z

    func test_titleToken_usesFirstLineOfTypedText() throws {
        let path = try plan("Inbox/{title}", payloads: [.text("Book recs from Sam\nThe Overstory")])
        XCTAssertEqual(path, "Inbox/Book recs from Sam.md")
    }

    func test_titleToken_stripsMarkdownMarkersAndUnsafeCharacters() throws {
        XCTAssertEqual(try plan("Inbox/{title}", payloads: [.text("## Q3: plan/review?")]), "Inbox/Q3 plan review.md")
        XCTAssertEqual(try plan("Inbox/{title}", payloads: [.text("- [ ] Call <Ana> | \"today\"")]), "Inbox/Call Ana today.md")
        XCTAssertEqual(try plan("Inbox/{title}", payloads: [.text("../../etc")]), "Inbox/etc.md")
    }

    func test_titleToken_skipsBlankLinesAndUsesLinkTitle() throws {
        XCTAssertEqual(try plan("Inbox/{title}", payloads: [.text("\n   \n#\nSecond line")]), "Inbox/Second line.md")
        XCTAssertEqual(
            try plan("Inbox/{title}", payloads: [.url(URL(string: "https://example.com/a")!, title: "Example Article")]),
            "Inbox/Example Article.md"
        )
    }

    func test_titleToken_fallsBackToTimestampWithoutText() throws {
        XCTAssertEqual(try plan("Inbox/{title}", payloads: []), "Inbox/2024-01-02-030405.md")
        XCTAssertEqual(try plan("Inbox/{title}", payloads: [.text("  /// ")]), "Inbox/2024-01-02-030405.md")
    }

    func test_titleToken_capsLengthAndKeepsMarkdownExtension() throws {
        let long = String(repeating: "word ", count: 40)
        let path = try plan("Inbox/{title}", payloads: [.text(long)])
        let title = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        XCTAssertLessThanOrEqual(title.count, CapturePathPlanner.maximumTitleLength)
        XCTAssertTrue(path.hasSuffix(".md"))
        XCTAssertEqual(try plan("Inbox/{title}", payloads: [.text("Release 2.5")]), "Inbox/Release 2.5.md")
    }

    func test_titleToken_doesNotRenderTokensInsideCaptureText() throws {
        XCTAssertEqual(try plan("Inbox/{title}", payloads: [.text("Notes {date}")]), "Inbox/Notes {date}.md")
    }

    func test_titleToken_newNoteStaysUnique() throws {
        let destination = makeDestination(target: .newNote(pathTemplate: "Inbox/{title}"))
        let request = makeRequest(payloads: [.text("Idea")])
        let path = try planner().relativePath(
            for: request,
            destination: destination,
            existingRelativePaths: ["Inbox/Idea.md"]
        )
        XCTAssertEqual(path, "Inbox/Idea-2.md")
    }

    private func plan(_ template: String, payloads: [CapturePayload]) throws -> String {
        try planner().relativePath(
            for: makeRequest(payloads: payloads),
            destination: makeDestination(target: .newNote(pathTemplate: template))
        )
    }

    private func planner() -> CapturePathPlanner {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return CapturePathPlanner(calendar: calendar)
    }

    private func makeRequest(payloads: [CapturePayload]) -> CaptureRequest {
        CaptureRequest(id: requestID, createdAt: date, source: .app, destinationID: destinationID, payloads: payloads)
    }

    private func makeDestination(target: CaptureNoteTarget) -> CaptureDestination {
        CaptureDestination(id: destinationID, name: "Test", rootBookmark: Data([1, 2, 3]), rootName: "Vault", noteTarget: target)
    }
}
