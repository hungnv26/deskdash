import Foundation

/// A calendar date with no time of day and no time zone.
///
/// Keeping the date part separate from any time means an all-day due date never
/// drifts to a neighbouring day when it passes through a time zone conversion.
struct TaskDueDate: Hashable, Codable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The local calendar date that `date` falls on.
    init(date: Date, calendar: Calendar = .autoupdatingCurrent) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Local midnight at the start of this date, for display and date pickers.
    func startOfDay(in calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    /// Calendar-day arithmetic done in UTC so daylight-saving shifts cannot skip or repeat a day.
    func adding(days: Int) -> TaskDueDate {
        let utc = Self.utcCalendar
        guard let start = utc.date(from: DateComponents(year: year, month: month, day: day)),
              let moved = utc.date(byAdding: .day, value: days, to: start) else { return self }
        return TaskDueDate(date: moved, calendar: utc)
    }

    static func today(calendar: Calendar = .autoupdatingCurrent, now: Date = Date()) -> TaskDueDate {
        TaskDueDate(date: now, calendar: calendar)
    }

    static func < (lhs: TaskDueDate, rhs: TaskDueDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
