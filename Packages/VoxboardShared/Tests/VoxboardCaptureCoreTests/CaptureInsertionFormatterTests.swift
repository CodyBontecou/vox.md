import Foundation
import XCTest
@testable import VoxboardCaptureCore

final class CaptureInsertionFormatterTests: XCTestCase {
    private let timeZone = TimeZone(identifier: "America/Los_Angeles")!
    private lazy var formatter = makeFormatter()

    func test_timestampFormatHasStablePersistedValuesAndTwelveHourDefault() throws {
        XCTAssertEqual(CaptureTimestampFormat.twelveHour.rawValue, "12-hour")
        XCTAssertEqual(CaptureTimestampFormat.twentyFourHour.rawValue, "24-hour")
        XCTAssertEqual(CaptureTimestampFormat.allCases, [.twelveHour, .twentyFourHour])
        XCTAssertEqual(CaptureTimestampFormat.default, .twelveHour)

        for format in CaptureTimestampFormat.allCases {
            XCTAssertEqual(CaptureTimestampFormat(rawValue: format.rawValue), format)
            XCTAssertEqual(format.id, format.rawValue)

            let encoded = try JSONEncoder().encode(format)
            XCTAssertEqual(String(data: encoded, encoding: .utf8), "\"\(format.rawValue)\"")
            XCTAssertEqual(try JSONDecoder().decode(CaptureTimestampFormat.self, from: encoded), format)
        }

        for storedValue in [nil, "retired"] as [String?] {
            let resolved = storedValue.flatMap { CaptureTimestampFormat(rawValue: $0) } ?? .default
            XCTAssertEqual(resolved, .twelveHour)
        }
    }

    func test_dueDateTokensAndCurrentTimestampUseInjectedClockDependencies() throws {
        let date = try localDate(2026, 1, 2, 15, 4)

        XCTAssertEqual(formatter.dueDateToken(for: date), "(@2026-01-02)")
        XCTAssertEqual(formatter.dueDateToken(for: date, includeTime: true), "(@2026-01-02 03:04 PM)")
        XCTAssertEqual(formatter.currentTimestamp(at: date), "3:04 PM 2026-01-02")
        XCTAssertEqual(formatter.timestamp(for: date), "3:04 PM 2026-01-02")
        XCTAssertEqual(
            formatter.currentTimestamp(at: date, format: .twelveHour),
            "3:04 PM 2026-01-02"
        )
        XCTAssertEqual(
            formatter.timestamp(for: date, format: .twentyFourHour),
            "15:04 2026-01-02"
        )
    }

    func test_timestampFormatsHandleMidnightNoonAndLeadingZeros() throws {
        let expectations: [(Date, twelveHour: String, twentyFourHour: String)] = [
            (try localDate(2026, 1, 2, 0, 4), "12:04 AM 2026-01-02", "00:04 2026-01-02"),
            (try localDate(2026, 1, 2, 3, 4), "3:04 AM 2026-01-02", "03:04 2026-01-02"),
            (try localDate(2026, 1, 2, 12, 4), "12:04 PM 2026-01-02", "12:04 2026-01-02"),
            (try localDate(2026, 1, 2, 15, 4), "3:04 PM 2026-01-02", "15:04 2026-01-02"),
        ]

        for (date, twelveHour, twentyFourHour) in expectations {
            XCTAssertEqual(formatter.currentTimestamp(at: date, format: .twelveHour), twelveHour)
            XCTAssertEqual(formatter.currentTimestamp(at: date, format: .twentyFourHour), twentyFourHour)
        }
    }

    func test_currentTimestampNoArgumentAPIStillUsesTwelveHourDefault() {
        let before = Date()
        let value = formatter.currentTimestamp()
        let after = Date()
        let validDefaultValues = [before, after].map {
            formatter.currentTimestamp(at: $0, format: .twelveHour)
        }

        XCTAssertTrue(validDefaultValues.contains(value), value)
    }

    func test_dateFormattingUsesInjectedLocaleAndTimeZoneRatherThanProcessDefaults() throws {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let utcFormatter = CaptureInsertionFormatter(
            calendar: utcCalendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let instant = try localDate(2026, 1, 2, 23, 30)

        XCTAssertEqual(formatter.dueDateToken(for: instant), "(@2026-01-02)")
        XCTAssertEqual(utcFormatter.dueDateToken(for: instant), "(@2026-01-03)")
        XCTAssertEqual(formatter.currentTimestamp(at: instant), "11:30 PM 2026-01-02")
        XCTAssertEqual(
            formatter.currentTimestamp(at: instant, format: .twentyFourHour),
            "23:30 2026-01-02"
        )
        XCTAssertEqual(utcFormatter.currentTimestamp(at: instant), "7:30 AM 2026-01-03")
        XCTAssertEqual(
            utcFormatter.currentTimestamp(at: instant, format: .twentyFourHour),
            "07:30 2026-01-03"
        )
        XCTAssertEqual(utcFormatter.calendar.identifier, utcCalendar.identifier)
        XCTAssertEqual(utcFormatter.locale.identifier, "en_US_POSIX")
        XCTAssertEqual(utcFormatter.timeZone.secondsFromGMT(for: instant), 0)
    }

    func test_wikiLinkStripsMarkdownExtensionAndNormalizesSeparators() throws {
        XCTAssertEqual(
            try formatter.wikiLink(for: " Projects\\Vox.md "),
            "[[Projects/Vox]]"
        )
        XCTAssertEqual(
            try formatter.wikiLink(for: "Projects//Ideas/Note.MD"),
            "[[Projects/Ideas/Note]]"
        )
    }

    func test_wikiLinkRejectsTraversalAbsoluteEmptyAndControlCharacterInputs() {
        let invalid = [
            "../Secrets.md",
            "Folder/../Secrets.md",
            "/Absolute.md",
            "\\Absolute.md",
            "C:\\Absolute.md",
            "~/.hidden.md",
            "Folder/Bad\nName.md",
            "Folder/Bad|Alias.md",
            "Folder/Bad]]Name.md",
            ".md",
        ]

        for value in invalid {
            XCTAssertThrowsError(try formatter.wikiLink(for: value), value) { error in
                XCTAssertEqual(error as? CaptureInsertionFormatterError, .invalidWikiLink)
            }
        }
    }

    func test_googleMapsLinkUsesPOSIXCoordinatesAndEscapesMarkdownLabel() throws {
        let result = try formatter.googleMapsLink(
            latitude: 21.3069,
            longitude: -157.8583,
            label: #"A [quiet] \\ place"#
        )

        XCTAssertEqual(
            result,
            #"[A \[quiet\] \\\\ place](https://www.google.com/maps?q=21.306900,-157.858300)"#
        )
    }

    func test_googleMapsLinkNeutralizesControlCharactersInLabel() throws {
        let result = try formatter.googleMapsLink(
            latitude: 0,
            longitude: 0,
            label: "First\u{0}Second\nThird"
        )

        XCTAssertEqual(
            result,
            "[First Second Third](https://www.google.com/maps?q=0.000000,0.000000)"
        )
    }

    func test_googleMapsLinkRejectsNonFiniteAndOutOfRangeCoordinates() {
        let invalid: [(Double, Double)] = [
            (.nan, 0),
            (0, .infinity),
            (90.0001, 0),
            (0, -180.0001),
        ]

        for (latitude, longitude) in invalid {
            XCTAssertThrowsError(
                try formatter.googleMapsLink(latitude: latitude, longitude: longitude, label: "Here")
            ) { error in
                XCTAssertEqual(error as? CaptureInsertionFormatterError, .invalidCoordinates)
            }
        }
    }

    func test_dueDateShortcutsUseCalendarAndPreserveLocalTime() throws {
        let wednesday = try localDate(2026, 7, 15, 9, 20)

        XCTAssertEqual(formatter.applying(.today, to: wednesday), wednesday)
        assertLocalComponents(
            formatter.applying(.tomorrow, to: wednesday),
            year: 2026,
            month: 7,
            day: 16,
            hour: 9,
            minute: 20
        )
        assertLocalComponents(
            formatter.applying(.thisWeekend, to: wednesday),
            year: 2026,
            month: 7,
            day: 18,
            hour: 9,
            minute: 20
        )

        let sunday = try localDate(2026, 7, 19, 9, 20)
        XCTAssertEqual(formatter.applying(.thisWeekend, to: sunday), sunday)
    }

    func test_minuteAdjustmentCrossesMidnightUsingCalendar() throws {
        let late = try localDate(2026, 1, 2, 23, 50)
        let adjusted = formatter.adjusting(late, by: 20, unit: .minute)

        assertLocalComponents(
            adjusted,
            year: 2026,
            month: 1,
            day: 3,
            hour: 0,
            minute: 10
        )
    }

    func test_hourAndDayMathHonorDaylightSavingTransitions() throws {
        let beforeSpringForward = try localDate(2026, 3, 8, 1, 30)
        assertLocalComponents(
            formatter.adjusting(beforeSpringForward, by: 1, unit: .hour),
            year: 2026,
            month: 3,
            day: 8,
            hour: 3,
            minute: 30
        )

        let dayBeforeSpringForward = try localDate(2026, 3, 7, 10, 15)
        assertLocalComponents(
            formatter.applying(.tomorrow, to: dayBeforeSpringForward),
            year: 2026,
            month: 3,
            day: 8,
            hour: 10,
            minute: 15
        )
    }

    private func makeFormatter() -> CaptureInsertionFormatter {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return CaptureInsertionFormatter(
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone
        )
    }

    private func localDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) throws -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return try XCTUnwrap(formatter.calendar.date(from: components))
    }

    private func assertLocalComponents(
        _ date: Date,
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let components = formatter.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        XCTAssertEqual(components.year, year, file: file, line: line)
        XCTAssertEqual(components.month, month, file: file, line: line)
        XCTAssertEqual(components.day, day, file: file, line: line)
        XCTAssertEqual(components.hour, hour, file: file, line: line)
        XCTAssertEqual(components.minute, minute, file: file, line: line)
    }
}
