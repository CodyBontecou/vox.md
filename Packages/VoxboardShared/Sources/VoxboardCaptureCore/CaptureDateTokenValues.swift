import Foundation

struct CaptureDateTokenValues: Sendable {
    let year: String
    let shortYear: String
    let month: String
    let day: String
    let hour: String
    let minute: String
    let second: String
    let weekYear: String
    let week: String

    init(date: Date, calendar: Calendar) {
        let calendar = Self.gregorian(matching: calendar)
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .weekOfYear, .yearForWeekOfYear],
            from: date
        )
        year = Self.padded(components.year, width: 4)
        shortYear = String(year.suffix(2))
        month = Self.padded(components.month, width: 2)
        day = Self.padded(components.day, width: 2)
        hour = Self.padded(components.hour, width: 2)
        minute = Self.padded(components.minute, width: 2)
        second = Self.padded(components.second, width: 2)
        weekYear = Self.padded(components.yearForWeekOfYear ?? components.year, width: 4)
        week = Self.padded(components.weekOfYear, width: 2)
    }

    var timestamp: String { "\(year)-\(month)-\(day)-\(hour)\(minute)\(second)" }
    var date: String { "\(year)-\(month)-\(day)" }
    var time: String { "\(hour)\(minute)\(second)" }
    var weekToken: String { "\(weekYear)-W\(week)" }

    /// Date tokens name vault files, so they must not depend on the device's
    /// calendar setting: a Hijri, Buddhist or Japanese calendar would otherwise
    /// write `1448-W21.md` instead of `2026-W45.md` and split one vault's notes
    /// across differently named files. The caller's time zone and week rules
    /// are kept so Gregorian users see no change.
    static func gregorian(matching calendar: Calendar) -> Calendar {
        guard calendar.identifier != .gregorian, calendar.identifier != .iso8601 else { return calendar }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        gregorian.locale = calendar.locale
        gregorian.firstWeekday = calendar.firstWeekday
        gregorian.minimumDaysInFirstWeek = calendar.minimumDaysInFirstWeek
        return gregorian
    }

    private static func padded(_ value: Int?, width: Int) -> String {
        String(format: "%0*d", width, value ?? 0)
    }
}
