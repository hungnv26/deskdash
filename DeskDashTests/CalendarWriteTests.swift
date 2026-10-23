import XCTest
@testable import DeskDash

final class EventDraftTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        return calendar
    }()

    private func date(_ d: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    func testNewDraftTodayStartsAtNextWholeHour() {
        let draft = EventDraft.new(on: date(20), calendarID: "c", now: date(20, 14, 25), calendar: calendar)
        XCTAssertEqual(draft.start, date(20, 15))
        XCTAssertEqual(draft.end, date(20, 16))
        XCTAssertFalse(draft.isAllDay)
    }

    func testNewDraftOnAnotherDayStartsAtNine() {
        let draft = EventDraft.new(on: date(22), calendarID: "c", now: date(20, 14), calendar: calendar)
        XCTAssertEqual(draft.start, date(22, 9))
    }

    func testAllDayDatesCoverWholeDays() {
        var draft = EventDraft.new(on: date(20), calendarID: "c", now: date(19), calendar: calendar)
        draft.isAllDay = true
        draft.start = date(20, 15)
        draft.end = date(22, 8)
        let dates = draft.normalizedDates(calendar: calendar)
        XCTAssertEqual(dates.start, date(20))
        XCTAssertEqual(dates.end, date(23), "Ends at midnight after the last day")
    }

    func testAllDayEventRoundTripsToItsLastDay() {
        let event = CalendarEvent(id: "e", calendarID: "c", calendarTitle: "C", title: "Trip",
                                  startDate: date(20), endDate: date(23), isAllDay: true)
        let draft = EventDraft(event: event)
        XCTAssertEqual(calendar.startOfDay(for: draft.end), date(22))
        XCTAssertEqual(draft.normalizedDates(calendar: calendar).end, date(23))
    }

    func testValidation() {
        var draft = EventDraft.new(on: date(20), calendarID: "c", now: date(19), calendar: calendar)
        XCTAssertEqual(draft.validationMessage(calendar: calendar), "Add a title.")
        draft.title = "Lunch"
        XCTAssertNil(draft.validationMessage(calendar: calendar))
        draft.end = draft.start
        XCTAssertNotNil(draft.validationMessage(calendar: calendar), "Zero-length timed event")
        draft.isAllDay = true
        XCTAssertNil(draft.validationMessage(calendar: calendar), "Single-day all-day event is fine")
    }
}

extension CalendarEvent {
    init(id: String, calendarID: String, calendarTitle: String, title: String, startDate: Date, endDate: Date, isAllDay: Bool) {
        self.init(id: id, calendarID: calendarID, calendarTitle: calendarTitle, calendarColor: nil, title: title,
                  startDate: startDate, endDate: endDate, isAllDay: isAllDay, location: nil, notes: nil, eventIdentifier: id)
    }
}

@MainActor
final class CalendarWriteStoreTests: XCTestCase {
    private var repository: MockCalendarRepository!
    private var store: CalendarStore!

    override func setUp() async throws {
        repository = MockCalendarRepository()
        let defaults = UserDefaults(suiteName: "DeskDashTests-\(UUID().uuidString)")!
        store = CalendarStore(repository: repository, preferences: PreferencesStore(defaults: defaults))
        await store.reload()
    }

    func testWritableCalendarsExcludeReadOnly() {
        XCTAssertFalse(store.writableCalendars.contains { $0.id == "holidays" })
        XCTAssertEqual(store.calendarForNewEvents?.id, "work")
    }

    func testCreateAddsEventAndSelectsItsDay() async throws {
        var draft = try XCTUnwrap(store.newEventDraft(on: Date().addingTimeInterval(3 * 86_400)))
        draft.title = "  Piano lesson  "
        draft.location = "Main St"
        let error = await store.createEvent(draft)
        XCTAssertNil(error)
        let created = try XCTUnwrap(store.events.first { $0.title == "Piano lesson" })
        XCTAssertEqual(created.location, "Main St")
        XCTAssertTrue(store.math.isSameDay(store.selectedDate, created.startDate))
    }

    func testCreateRejectsInvalidDraft() async throws {
        let draft = try XCTUnwrap(store.newEventDraft())
        let error = await store.createEvent(draft)
        XCTAssertEqual(error, "Add a title.")
        XCTAssertEqual(repository.writeCount, 0)
    }

    func testEditOnlyWritesChangedFields() async throws {
        let event = try XCTUnwrap(store.events.first { $0.id == "review-0" })
        let base = EventDraft(event: event)
        // Someone edits the notes on their phone after we opened the editor.
        repository.externalEdit(id: "review-0") { $0.notes = "Edited on iPhone" }
        var draft = base
        draft.title = "Design review (moved)"
        let error = await store.updateEvent(event, from: base, to: draft, span: .thisEvent)
        XCTAssertNil(error)
        let saved = try XCTUnwrap(repository.allEvents.first { $0.id == "review-0" })
        XCTAssertEqual(saved.title, "Design review (moved)")
        XCTAssertEqual(saved.notes, "Edited on iPhone")
    }

    func testMovingAnEventChangesItsTimes() async throws {
        let event = try XCTUnwrap(store.events.first { $0.id == "gym-0" })
        let base = EventDraft(event: event)
        var draft = base
        draft.start = base.start.addingTimeInterval(3600)
        draft.end = base.end.addingTimeInterval(3600)
        let error = await store.updateEvent(event, from: base, to: draft, span: .thisEvent)
        XCTAssertNil(error)
        let saved = try XCTUnwrap(repository.allEvents.first { $0.id == "gym-0" })
        XCTAssertEqual(saved.startDate, event.startDate.addingTimeInterval(3600))
    }

    func testReadOnlyEventCannotBeEdited() async throws {
        let all = repository.allEvents
        let holiday = try XCTUnwrap(all.first { $0.id == "holiday" })
        XCTAssertFalse(holiday.isEditable)
        var draft = EventDraft(event: holiday)
        draft.title = "Mine now"
        let error = await store.updateEvent(holiday, from: EventDraft(event: holiday), to: draft, span: .thisEvent)
        XCTAssertNotNil(error)
        XCTAssertEqual(repository.writeCount, 0)
    }

    func testCreatingInHiddenCalendarExplains() async throws {
        store.setVisible(false, calendar: try XCTUnwrap(store.calendars.first { $0.id == "personal" }))
        var draft = try XCTUnwrap(store.newEventDraft())
        draft.title = "Secret"
        draft.calendarID = "personal"
        let error = await store.createEvent(draft)
        XCTAssertNil(error)
        XCTAssertNotNil(store.notice)
    }
}

@MainActor
final class EventRepeatTests: XCTestCase {
    private var repository: MockCalendarRepository!
    private var store: CalendarStore!

    override func setUp() async throws {
        repository = MockCalendarRepository()
        store = CalendarStore(repository: repository, preferences: PreferencesStore(defaults: UserDefaults(suiteName: "DeskDashTests-\(UUID().uuidString)")!))
        await store.reload()
    }

    func testCreateWeeklyEventWithEndDate() async throws {
        var draft = try XCTUnwrap(store.newEventDraft())
        draft.title = "Team lunch"
        let end = Calendar.current.date(byAdding: .month, value: 2, to: draft.start)!
        draft.repeatRule = EventRepeat(frequency: .weekly, endDate: end)
        let error = await store.createEvent(draft)
        XCTAssertNil(error)
        let saved = try XCTUnwrap(repository.allEvents.first { $0.title == "Team lunch" })
        XCTAssertTrue(saved.isRecurring)
        XCTAssertEqual(saved.repeatRule.frequency, .weekly)
        XCTAssertEqual(saved.repeatRule.endDate, end)
    }

    func testChangingRepeatOnExistingEvent() async throws {
        let event = try XCTUnwrap(store.events.first { $0.id == "review-0" })
        let base = EventDraft(event: event)
        var draft = base
        draft.repeatRule = EventRepeat(frequency: .monthly, endDate: nil)
        let error = await store.updateEvent(event, from: base, to: draft, span: .thisEvent)
        XCTAssertNil(error)
        XCTAssertEqual(repository.allEvents.first { $0.id == "review-0" }?.repeatRule.frequency, .monthly)
    }

    func testStoppingARepeat() async throws {
        let gym = try XCTUnwrap(store.events.first { $0.id == "gym-0" })
        XCTAssertEqual(gym.repeatRule.frequency, .weekly)
        let base = EventDraft(event: gym)
        var draft = base
        draft.repeatRule = .never
        let error = await store.updateEvent(gym, from: base, to: draft, span: .futureEvents)
        XCTAssertNil(error)
        XCTAssertFalse(repository.allEvents.first { $0.id == "gym-0" }!.isRecurring)
    }

    func testCustomRepeatIsLeftAlone() async throws {
        repository.externalEdit(id: "plan") { $0.repeatRule = EventRepeat(frequency: .custom, endDate: nil); $0.isRecurring = true }
        await store.reload()
        let event = try XCTUnwrap(repository.allEvents.first { $0.id == "plan" })
        let base = EventDraft(event: event)
        var draft = base
        draft.title = "Sprint planning (room 2)"
        let error = await store.updateEvent(event, from: base, to: draft, span: .thisEvent)
        XCTAssertNil(error)
        XCTAssertEqual(repository.allEvents.first { $0.id == "plan" }?.repeatRule.frequency, .custom)
    }

    func testRepeatEndBeforeStartIsRejected() throws {
        var draft = try XCTUnwrap(store.newEventDraft())
        draft.title = "x"
        draft.repeatRule = EventRepeat(frequency: .daily, endDate: draft.start.addingTimeInterval(-3 * 86_400))
        XCTAssertNotNil(draft.validationMessage())
    }

    func testSummaries() {
        XCTAssertNil(EventRepeat.never.summary)
        XCTAssertEqual(EventRepeat(frequency: .biweekly, endDate: nil).summary, "Repeats every 2 weeks")
        XCTAssertTrue(EventRepeat(frequency: .yearly, endDate: Date()).summary!.hasPrefix("Repeats every year until "))
        XCTAssertEqual(EventRepeat(frequency: .custom, endDate: nil).summary, "Repeats on a custom schedule")
    }
}
