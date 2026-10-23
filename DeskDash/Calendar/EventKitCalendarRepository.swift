import AppKit
@preconcurrency import EventKit

/// The app's single `EKEventStore`, shared by calendar and reminders, plus the
/// serial queue every store access runs on.
final class EventStoreHub: @unchecked Sendable {
    let store = EKEventStore()
    let queue = DispatchQueue(label: "net.hungngo.DeskDash.eventkit", qos: .userInitiated)

    /// Fires whenever anything in the store changes, including iCloud sync from other devices.
    func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let token = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: nil) { _ in
                continuation.yield()
            }
            nonisolated(unsafe) let unsafeToken = token
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(unsafeToken)
            }
        }
    }
}

/// EventKit-backed calendar repository: reads, creates and edits events (never deletes).
///
/// Writes go to the Mac's calendar store, and the calendar's account (iCloud, Google,
/// Exchange…) syncs them to other devices. `EKEvent`s are converted to immutable `CalendarEvent` values before leaving the hub's queue.
final class EventKitCalendarRepository: CalendarRepository, @unchecked Sendable {
    private let hub: EventStoreHub
    private var store: EKEventStore { hub.store }
    private var queue: DispatchQueue { hub.queue }

    init(hub: EventStoreHub) {
        self.hub = hub
    }

    func authorizationState() -> CalendarAuthState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess: .granted
        case .writeOnly: .writeOnly
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }

    func requestAccess() async -> CalendarAuthState {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            Log.calendar.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
        }
        return authorizationState()
    }

    func calendars() async -> [CalendarSource] {
        await withCheckedContinuation { continuation in
            queue.async {
                let result = self.store.calendars(for: .event).map { calendar in
                    CalendarSource(
                        id: calendar.calendarIdentifier,
                        title: calendar.title,
                        accountTitle: calendar.source?.title ?? "Other",
                        color: RGBAColor(calendar.color),
                        allowsModifications: calendar.allowsContentModifications
                    )
                }
                continuation.resume(returning: result.sorted { ($0.accountTitle, $0.title) < ($1.accountTitle, $1.title) })
            }
        }
    }

    func events(in interval: DateInterval, calendarIDs: Set<String>?) async -> [CalendarEvent] {
        await withCheckedContinuation { continuation in
            queue.async {
                let started = Date()
                let calendars = self.store.calendars(for: .event).filter { calendarIDs?.contains($0.calendarIdentifier) ?? true }
                guard !calendars.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }
                let predicate = self.store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
                let events = self.store.events(matching: predicate).map(Self.makeEvent)
                Log.calendar.debug("Fetched \(events.count) events in \(Date().timeIntervalSince(started), format: .fixed(precision: 3))s")
                continuation.resume(returning: events)
            }
        }
    }

    func changes() -> AsyncStream<Void> {
        hub.changes()
    }

    // MARK: - Writes

    func defaultCalendarID() async -> String? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.store.defaultCalendarForNewEvents?.calendarIdentifier) }
        }
    }

    func createEvent(_ draft: EventDraft) async throws -> CalendarEvent {
        if let message = draft.validationMessage() { throw CalendarWriteError.invalid(message) }
        return try await onQueueThrowing {
            guard let calendar = self.store.calendar(withIdentifier: draft.calendarID) ?? self.store.defaultCalendarForNewEvents else {
                throw CalendarWriteError.invalid("Choose a calendar for the event.")
            }
            guard calendar.allowsContentModifications else {
                throw CalendarWriteError.readOnly("“\(calendar.title)” is read-only. Choose another calendar.")
            }
            let event = EKEvent(eventStore: self.store)
            event.calendar = calendar
            event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            Self.applyDates(draft, to: event)
            event.location = draft.location.nilIfBlank
            event.notes = draft.notes.nilIfBlank
            Self.applyRepeat(draft.repeatRule, to: event)
            try self.save(event, span: .thisEvent)
            return Self.makeEvent(event)
        }
    }

    func updateEvent(_ event: CalendarEvent, from base: EventDraft, to draft: EventDraft, span: EventSpan) async throws -> CalendarEvent {
        if let message = draft.validationMessage() { throw CalendarWriteError.invalid(message) }
        return try await onQueueThrowing {
            let target = try self.occurrence(of: event)
            if let reason = Self.readOnlyReason(target) { throw CalendarWriteError.readOnly(reason) }

            if base.title != draft.title { target.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            if base.isAllDay != draft.isAllDay || base.start != draft.start || base.end != draft.end {
                Self.applyDates(draft, to: target)
            }
            if base.location != draft.location { target.location = draft.location.nilIfBlank }
            if base.notes != draft.notes { target.notes = draft.notes.nilIfBlank }
            if base.calendarID != draft.calendarID {
                guard let calendar = self.store.calendar(withIdentifier: draft.calendarID), calendar.allowsContentModifications else {
                    throw CalendarWriteError.readOnly("That calendar is read-only. Choose another calendar.")
                }
                target.calendar = calendar
            }
            let repeatChanged = base.repeatRule != draft.repeatRule && draft.repeatRule.frequency != .custom
            let wasRecurring = target.hasRecurrenceRules
            if repeatChanged { Self.applyRepeat(draft.repeatRule, to: target) }
            // A changed repeat always applies to this and future occurrences, as in Calendar.
            let saveSpan: EKSpan = (wasRecurring && (span == .futureEvents || repeatChanged)) ? .futureEvents : .thisEvent
            try self.save(target, span: saveSpan)
            return Self.makeEvent(target)
        }
    }

    /// Finds the exact occurrence shown on screen (repeating events share one identifier).
    private func occurrence(of event: CalendarEvent) throws -> EKEvent {
        guard let identifier = event.eventIdentifier else { throw CalendarWriteError.notFound }
        if !event.isRecurring, let found = store.event(withIdentifier: identifier) { return found }
        let anchor = event.occurrenceDate ?? event.startDate
        let calendars = store.calendar(withIdentifier: event.calendarID).map { [$0] }
        let predicate = store.predicateForEvents(withStart: anchor.addingTimeInterval(-86_400), end: anchor.addingTimeInterval(2 * 86_400), calendars: calendars)
        let candidates = store.events(matching: predicate).filter { $0.eventIdentifier == identifier }
        guard let match = candidates.first(where: { $0.occurrenceDate == anchor }) ?? candidates.first(where: { $0.startDate == event.startDate }) else {
            throw CalendarWriteError.notFound
        }
        return match
    }

    /// All-day events are stored as whole days ending at 23:59:59 on the last day,
    /// which is how EventKit itself reports them.
    private static func applyDates(_ draft: EventDraft, to event: EKEvent) {
        let dates = draft.normalizedDates()
        event.isAllDay = draft.isAllDay
        event.startDate = dates.start
        event.endDate = draft.isAllDay ? dates.end.addingTimeInterval(-1) : dates.end
    }

    /// Replaces the event's repeat with a simple rule. `.custom` is never written.
    private static func applyRepeat(_ rule: EventRepeat, to event: EKEvent) {
        guard rule.frequency != .custom else { return }
        for existing in event.recurrenceRules ?? [] { event.removeRecurrenceRule(existing) }
        let pattern: (EKRecurrenceFrequency, Int)?
        switch rule.frequency {
        case .daily: pattern = (.daily, 1)
        case .weekly: pattern = (.weekly, 1)
        case .biweekly: pattern = (.weekly, 2)
        case .monthly: pattern = (.monthly, 1)
        case .yearly: pattern = (.yearly, 1)
        case .never, .custom: pattern = nil
        }
        guard let (frequency, interval) = pattern else { return }
        // The end date is inclusive: occurrences on that day still happen.
        let end = rule.endDate.map { date -> EKRecurrenceEnd in
            let calendar = Calendar.autoupdatingCurrent
            let lastMoment = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: date)) ?? date
            return EKRecurrenceEnd(end: lastMoment)
        }
        event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: frequency, interval: interval, end: end))
    }

    /// Maps EventKit's rule to the simple choices, or `.custom` for anything richer.
    private static func repeatRule(of event: EKEvent) -> EventRepeat {
        guard let rules = event.recurrenceRules, !rules.isEmpty else { return .never }
        guard rules.count == 1, let rule = rules.first,
              rule.daysOfTheWeek == nil, rule.daysOfTheMonth == nil, rule.daysOfTheYear == nil,
              rule.weeksOfTheYear == nil, rule.monthsOfTheYear == nil, rule.setPositions == nil,
              rule.recurrenceEnd?.occurrenceCount ?? 0 == 0 else {
            return EventRepeat(frequency: .custom, endDate: nil)
        }
        let frequency: RepeatFrequency
        switch (rule.frequency, rule.interval) {
        case (.daily, 1): frequency = .daily
        case (.weekly, 1): frequency = .weekly
        case (.weekly, 2): frequency = .biweekly
        case (.monthly, 1): frequency = .monthly
        case (.yearly, 1): frequency = .yearly
        default: frequency = .custom
        }
        return EventRepeat(frequency: frequency, endDate: frequency == .custom ? nil : rule.recurrenceEnd?.endDate)
    }

    private func save(_ event: EKEvent, span: EKSpan) throws {
        do {
            try store.save(event, span: span, commit: true)
        } catch {
            Log.calendar.error("Saving an event failed: \(error.localizedDescription, privacy: .public)")
            throw CalendarWriteError.saveFailed(error.localizedDescription)
        }
    }

    private static func readOnlyReason(_ event: EKEvent) -> String? {
        guard event.calendar?.allowsContentModifications ?? false else {
            return "“\(event.calendar?.title ?? "This calendar")” is read-only, so its events can't be changed here."
        }
        if let organizer = event.organizer, !organizer.isCurrentUser {
            let name = organizer.name ?? "someone else"
            return "This is an invitation from \(name). Change it in the Calendar app so they're notified."
        }
        return nil
    }

    private func onQueueThrowing<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    private static func makeEvent(_ event: EKEvent) -> CalendarEvent {
        let baseID = event.eventIdentifier ?? event.calendarItemIdentifier
        return CalendarEvent(
            id: "\(baseID)|\(event.startDate.timeIntervalSince1970)",
            calendarID: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            calendarColor: RGBAColor(event.calendar.color),
            title: (event.title?.isEmpty == false ? event.title : nil) ?? "Untitled event",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location?.nilIfBlank,
            notes: event.notes?.nilIfBlank,
            eventIdentifier: event.eventIdentifier,
            occurrenceDate: event.occurrenceDate,
            isRecurring: event.hasRecurrenceRules,
            repeatRule: repeatRule(of: event),
            readOnlyReason: readOnlyReason(event)
        )
    }
}

extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
