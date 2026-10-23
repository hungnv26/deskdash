import Foundation

/// In-memory calendar data for demo mode, previews and tests.
final class MockCalendarRepository: CalendarRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var state: CalendarAuthState
    private var sources: [CalendarSource]
    private var storedEvents: [CalendarEvent]

    init(state: CalendarAuthState = .granted, sources: [CalendarSource]? = nil, events: [CalendarEvent]? = nil, now: Date = Date()) {
        self.state = state
        let defaults = Self.sampleSources
        self.sources = sources ?? defaults
        self.storedEvents = events ?? Self.sampleEvents(around: now, sources: defaults)
    }

    func authorizationState() -> CalendarAuthState { lock.withLock { state } }

    func requestAccess() async -> CalendarAuthState {
        lock.withLock {
            if state == .notDetermined { state = .granted }
            return state
        }
    }

    func calendars() async -> [CalendarSource] {
        lock.withLock { state == .granted ? sources : [] }
    }

    func events(in interval: DateInterval, calendarIDs: Set<String>?) async -> [CalendarEvent] {
        lock.withLock {
            guard state == .granted else { return [] }
            return storedEvents.filter { event in
                (calendarIDs?.contains(event.calendarID) ?? true)
                    && event.startDate < interval.end
                    && (event.endDate > interval.start || event.startDate >= interval.start)
            }
        }
    }

    func changes() -> AsyncStream<Void> {
        AsyncStream { _ in }
    }

    // MARK: - Writes

    private(set) var writeCount = 0
    private var nextID = 1

    var allEvents: [CalendarEvent] { lock.withLock { storedEvents } }

    func defaultCalendarID() async -> String? {
        lock.withLock { sources.first(where: \.allowsModifications)?.id }
    }

    func createEvent(_ draft: EventDraft) async throws -> CalendarEvent {
        if let message = draft.validationMessage() { throw CalendarWriteError.invalid(message) }
        return try lock.withLock {
            guard let source = sources.first(where: { $0.id == draft.calendarID }) else { throw CalendarWriteError.invalid("Choose a calendar for the event.") }
            guard source.allowsModifications else { throw CalendarWriteError.readOnly("“\(source.title)” is read-only. Choose another calendar.") }
            writeCount += 1
            nextID += 1
            let dates = draft.normalizedDates()
            let event = CalendarEvent(
                id: "new-\(nextID)", calendarID: source.id, calendarTitle: source.title, calendarColor: source.color,
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines), startDate: dates.start, endDate: dates.end,
                isAllDay: draft.isAllDay, location: draft.location.nilIfBlank, notes: draft.notes.nilIfBlank,
                eventIdentifier: "new-\(nextID)", occurrenceDate: dates.start,
                isRecurring: draft.repeatRule.repeats, repeatRule: draft.repeatRule
            )
            storedEvents.append(event)
            return event
        }
    }

    func updateEvent(_ event: CalendarEvent, from base: EventDraft, to draft: EventDraft, span: EventSpan) async throws -> CalendarEvent {
        if let message = draft.validationMessage() { throw CalendarWriteError.invalid(message) }
        return try lock.withLock {
            guard let index = storedEvents.firstIndex(where: { $0.id == event.id }) else { throw CalendarWriteError.notFound }
            if let reason = storedEvents[index].readOnlyReason { throw CalendarWriteError.readOnly(reason) }
            writeCount += 1
            var updated = storedEvents[index]
            if base.title != draft.title { updated.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            if base.isAllDay != draft.isAllDay || base.start != draft.start || base.end != draft.end {
                let dates = draft.normalizedDates()
                updated.isAllDay = draft.isAllDay
                updated.startDate = dates.start
                updated.endDate = dates.end
            }
            if base.location != draft.location { updated.location = draft.location.nilIfBlank }
            if base.notes != draft.notes { updated.notes = draft.notes.nilIfBlank }
            if base.repeatRule != draft.repeatRule, draft.repeatRule.frequency != .custom {
                updated.repeatRule = draft.repeatRule
                updated.isRecurring = draft.repeatRule.repeats
            }
            if base.calendarID != draft.calendarID, let source = sources.first(where: { $0.id == draft.calendarID }) {
                updated.calendarID = source.id
                updated.calendarTitle = source.title
                updated.calendarColor = source.color
            }
            storedEvents[index] = updated
            return updated
        }
    }

    /// Simulates an edit synced in from another device.
    func externalEdit(id: String, _ change: (inout CalendarEvent) -> Void) {
        lock.withLock {
            guard let index = storedEvents.firstIndex(where: { $0.id == id }) else { return }
            change(&storedEvents[index])
        }
    }

    // MARK: - Sample data

    static let sampleSources: [CalendarSource] = [
        CalendarSource(id: "work", title: "Work", accountTitle: "iCloud", color: RGBAColor(red: 0.20, green: 0.48, blue: 0.96)),
        CalendarSource(id: "personal", title: "Personal", accountTitle: "iCloud", color: RGBAColor(red: 0.20, green: 0.70, blue: 0.40)),
        CalendarSource(id: "family", title: "Family", accountTitle: "Google", color: RGBAColor(red: 0.96, green: 0.58, blue: 0.16)),
        CalendarSource(id: "holidays", title: "Holidays", accountTitle: "Subscribed", color: RGBAColor(red: 0.55, green: 0.45, blue: 0.85), allowsModifications: false),
    ]

    static func sampleEvents(around now: Date, sources: [CalendarSource], calendar: Calendar = .autoupdatingCurrent) -> [CalendarEvent] {
        let today = calendar.startOfDay(for: now)
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        func event(_ id: String, _ source: Int, _ title: String, _ start: Date, _ end: Date, allDay: Bool = false, location: String? = nil, notes: String? = nil, repeats: EventRepeat = .never) -> CalendarEvent {
            let s = sources[source]
            return CalendarEvent(id: id, calendarID: s.id, calendarTitle: s.title, calendarColor: s.color, title: title,
                                 startDate: start, endDate: end, isAllDay: allDay, location: location, notes: notes,
                                 eventIdentifier: id, occurrenceDate: start,
                                 isRecurring: repeats.repeats, repeatRule: repeats,
                                 readOnlyReason: s.allowsModifications ? nil : "“\(s.title)” is read-only, so its events can't be changed here.")
        }

        var events: [CalendarEvent] = [
            event("standup-0", 0, "Team stand-up", at(0, 9), at(0, 9, 15), location: "Zoom"),
            event("review-0", 0, "Design review", at(0, 11), at(0, 12), location: "Level 3 · Room B", notes: "Bring the Q4 dashboard mock-ups."),
            event("lunch-0", 1, "Lunch with Minh", at(0, 12, 30), at(0, 13, 30), location: "Bánh Mì Bar"),
            event("focus-0", 0, "Focus block", at(0, 14), at(0, 16)),
            event("gym-0", 1, "Gym", at(0, 18), at(0, 19), repeats: EventRepeat(frequency: .weekly, endDate: nil)),
            event("bday", 2, "Mum's birthday", day(2), day(3), allDay: true),
            event("conf", 0, "Product summit", day(4), day(7), allDay: true, location: "Sydney"),
            event("flight", 1, "Overnight flight", at(5, 22), at(6, 6, 30), location: "SYD → SGN"),
            event("dentist", 1, "Dentist", at(-3, 15), at(-3, 16)),
            event("school", 2, "School pickup", at(1, 15), at(1, 15, 30)),
            event("plan", 0, "Sprint planning", at(1, 10), at(1, 11, 30)),
            event("holiday", 3, "Public holiday", day(-8), day(-7), allDay: true),
        ]
        for offset in [-6, -5, -2, -1, 3, 8, 9, 10, 15, 16, 17] {
            events.append(event("standup\(offset)", 0, "Team stand-up", at(offset, 9), at(offset, 9, 15), location: "Zoom"))
        }
        events.append(event("allday-0", 2, "Bin night", day(0), day(1), allDay: true))
        return events
    }
}
