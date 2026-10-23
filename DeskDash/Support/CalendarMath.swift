import Foundation

/// Day and month arithmetic in the user's calendar and time zone.
///
/// Everything goes through `Calendar` rather than fixed 86,400-second days, so
/// daylight-saving transitions (23- and 25-hour days) are handled correctly.
struct CalendarMath: Sendable {
    var calendar: Calendar

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func dayInterval(containing date: Date) -> DateInterval {
        let start = startOfDay(date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    func startOfMonth(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? startOfDay(date)
    }

    func monthInterval(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .month, for: date) ?? dayInterval(containing: date)
    }

    func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    func isSameMonth(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, equalTo: rhs, toGranularity: .month)
    }

    /// The 42 days (six weeks) shown in a month grid, starting on the user's first weekday.
    func monthGridDays(for month: Date) -> [Date] {
        let first = startOfMonth(month)
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: first) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    /// The range of time covered by the month grid, used to bound EventKit queries.
    func gridInterval(for month: Date) -> DateInterval {
        let days = monthGridDays(for: month)
        guard let first = days.first, let last = days.last else { return monthInterval(containing: month) }
        return DateInterval(start: first, end: dayInterval(containing: last).end)
    }

    /// Short weekday symbols ordered from the user's first weekday.
    var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    /// Whether an event is on screen for `day`. Events that end exactly at midnight
    /// do not spill into the next day; zero-length events count on the day they start.
    func occurs(_ event: CalendarEvent, on day: Date) -> Bool {
        let interval = dayInterval(containing: day)
        if event.endDate <= event.startDate {
            return event.startDate >= interval.start && event.startDate < interval.end
        }
        return event.startDate < interval.end && event.endDate > interval.start
    }

    /// The day agenda: all-day events first, then timed events by start time.
    func agenda(for day: Date, from events: [CalendarEvent]) -> (allDay: [CalendarEvent], timed: [CalendarEvent]) {
        let todays = events.filter { occurs($0, on: day) }
        let allDay = todays.filter(\.isAllDay).sorted { ($0.title, $0.id) < ($1.title, $1.id) }
        let timed = todays.filter { !$0.isAllDay }.sorted {
            if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
            if $0.endDate != $1.endDate { return $0.endDate < $1.endDate }
            return $0.title < $1.title
        }
        return (allDay, timed)
    }

    /// Events grouped by the start of each day they appear on.
    func eventsByDay(_ events: [CalendarEvent], days: [Date]) -> [Date: [CalendarEvent]] {
        var result: [Date: [CalendarEvent]] = [:]
        for day in days {
            let key = startOfDay(day)
            let matches = events.filter { occurs($0, on: key) }
            if !matches.isEmpty { result[key] = matches }
        }
        return result
    }
}
