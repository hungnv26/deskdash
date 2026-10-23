import XCTest
@testable import DeskDash

final class TaskDueDateTests: XCTestCase {
    /// An all-day date must not become "yesterday" west of UTC or "tomorrow" east of it.
    func testDueDateDoesNotShiftAcrossTimeZones() {
        let due = TaskDueDate(year: 2026, month: 3, day: 1)
        for identifier in ["America/Los_Angeles", "Pacific/Honolulu", "Asia/Ho_Chi_Minh", "Australia/Sydney", "Pacific/Kiritimati"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: identifier)!
            let local = due.startOfDay(in: calendar)
            XCTAssertEqual(TaskDueDate(date: local, calendar: calendar), due, identifier)
        }
    }

    func testAddingDaysAcrossLeapDayAndYearEnd() {
        XCTAssertEqual(TaskDueDate(year: 2028, month: 2, day: 28).adding(days: 1), TaskDueDate(year: 2028, month: 2, day: 29))
        XCTAssertEqual(TaskDueDate(year: 2028, month: 2, day: 29).adding(days: 1), TaskDueDate(year: 2028, month: 3, day: 1))
        XCTAssertEqual(TaskDueDate(year: 2026, month: 12, day: 31).adding(days: 1), TaskDueDate(year: 2027, month: 1, day: 1))
        XCTAssertEqual(TaskDueDate(year: 2027, month: 1, day: 1).adding(days: -1), TaskDueDate(year: 2026, month: 12, day: 31))
    }

    func testOrdering() {
        XCTAssertLessThan(TaskDueDate(year: 2026, month: 1, day: 31), TaskDueDate(year: 2026, month: 2, day: 1))
        XCTAssertLessThan(TaskDueDate(year: 2025, month: 12, day: 31), TaskDueDate(year: 2026, month: 1, day: 1))
    }
}

final class CalendarMathTests: XCTestCase {
    private func calendar(_ zone: String, firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, calendarID: "c", calendarTitle: "C", calendarColor: nil, title: id, startDate: start, endDate: end, isAllDay: allDay, location: nil, notes: nil)
    }

    func testDSTDaysAreTwentyThreeAndTwentyFiveHours() {
        let sydney = CalendarMath(calendar: calendar("Australia/Sydney"))
        // DST starts first Sunday of October 2026 (4 Oct) and ends first Sunday of April 2026 (5 Apr).
        XCTAssertEqual(sydney.dayInterval(containing: date(sydney.calendar, 2026, 10, 4, 12)).duration, 23 * 3600)
        XCTAssertEqual(sydney.dayInterval(containing: date(sydney.calendar, 2026, 4, 5, 12)).duration, 25 * 3600)
        let newYork = CalendarMath(calendar: calendar("America/New_York"))
        XCTAssertEqual(newYork.dayInterval(containing: date(newYork.calendar, 2026, 3, 8, 12)).duration, 23 * 3600)
    }

    func testMonthGridStartsOnFirstWeekdayAndHasSixWeeks() {
        let math = CalendarMath(calendar: calendar("Australia/Sydney", firstWeekday: 2))
        let days = math.monthGridDays(for: date(math.calendar, 2026, 10, 15))
        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(math.calendar.component(.weekday, from: days[0]), 2, "Monday")
        XCTAssertEqual(math.calendar.dateComponents([.month, .day], from: days[0]), DateComponents(month: 9, day: 28))
        // Every cell is a local midnight, even across the October DST change.
        for day in days { XCTAssertEqual(math.startOfDay(day), day) }

        let sundayFirst = CalendarMath(calendar: calendar("America/New_York", firstWeekday: 1))
        let febDays = sundayFirst.monthGridDays(for: date(sundayFirst.calendar, 2026, 2, 10))
        XCTAssertEqual(sundayFirst.calendar.component(.weekday, from: febDays[0]), 1, "Sunday")
    }

    func testAllDayEventStaysOnItsDate() {
        let math = CalendarMath(calendar: calendar("America/Los_Angeles"))
        let day = date(math.calendar, 2026, 10, 19)
        let next = date(math.calendar, 2026, 10, 20)
        let allDay = event("allday", day, next, allDay: true)
        XCTAssertTrue(math.occurs(allDay, on: day))
        XCTAssertFalse(math.occurs(allDay, on: next), "Ending at midnight must not spill into the next day")
        XCTAssertFalse(math.occurs(allDay, on: date(math.calendar, 2026, 10, 18)))
    }

    func testEventCrossingMidnightAppearsOnBothDays() {
        let math = CalendarMath(calendar: calendar("Asia/Ho_Chi_Minh"))
        let flight = event("flight", date(math.calendar, 2026, 10, 19, 22), date(math.calendar, 2026, 10, 20, 6, 30))
        XCTAssertTrue(math.occurs(flight, on: date(math.calendar, 2026, 10, 19)))
        XCTAssertTrue(math.occurs(flight, on: date(math.calendar, 2026, 10, 20)))
        XCTAssertFalse(math.occurs(flight, on: date(math.calendar, 2026, 10, 21)))
    }

    func testZeroLengthEventCountsOnStartDay() {
        let math = CalendarMath(calendar: calendar("UTC"))
        let reminder = event("r", date(math.calendar, 2026, 10, 19, 9), date(math.calendar, 2026, 10, 19, 9))
        XCTAssertTrue(math.occurs(reminder, on: date(math.calendar, 2026, 10, 19)))
    }

    func testAgendaPutsAllDayFirstThenChronological() {
        let math = CalendarMath(calendar: calendar("UTC"))
        let day = date(math.calendar, 2026, 10, 19)
        let events = [
            event("late", date(math.calendar, 2026, 10, 19, 15), date(math.calendar, 2026, 10, 19, 16)),
            event("early", date(math.calendar, 2026, 10, 19, 8), date(math.calendar, 2026, 10, 19, 9)),
            event("allday", day, date(math.calendar, 2026, 10, 20), allDay: true),
            event("otherday", date(math.calendar, 2026, 10, 21, 8), date(math.calendar, 2026, 10, 21, 9)),
        ]
        let agenda = math.agenda(for: day, from: events)
        XCTAssertEqual(agenda.allDay.map(\.id), ["allday"])
        XCTAssertEqual(agenda.timed.map(\.id), ["early", "late"])
    }

    func testLeapDayInMonthGrid() {
        let math = CalendarMath(calendar: calendar("UTC"))
        let days = math.monthGridDays(for: date(math.calendar, 2028, 2, 1))
        XCTAssertTrue(days.contains(date(math.calendar, 2028, 2, 29)))
    }
}
