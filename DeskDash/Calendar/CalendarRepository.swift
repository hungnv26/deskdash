import Foundation

/// Calendar events: read, create and edit (no delete). Views and stores only see this protocol.
protocol CalendarRepository: AnyObject, Sendable {
    func authorizationState() -> CalendarAuthState
    /// Asks for access. Only call from an explicit user action.
    func requestAccess() async -> CalendarAuthState
    func calendars() async -> [CalendarSource]
    /// Events overlapping `interval`. `calendarIDs == nil` means every calendar.
    func events(in interval: DateInterval, calendarIDs: Set<String>?) async -> [CalendarEvent]
    /// Fires whenever the underlying calendar store changes.
    func changes() -> AsyncStream<Void>
    /// The calendar new events go to by default (set in the Calendar app).
    func defaultCalendarID() async -> String?
    func createEvent(_ draft: EventDraft) async throws -> CalendarEvent
    /// Writes only the fields that differ between `base` and `draft`, so a change made on
    /// another device to a different field is never overwritten.
    func updateEvent(_ event: CalendarEvent, from base: EventDraft, to draft: EventDraft, span: EventSpan) async throws -> CalendarEvent
}
