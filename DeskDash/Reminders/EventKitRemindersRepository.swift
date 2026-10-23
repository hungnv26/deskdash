import AppKit
@preconcurrency import EventKit

/// Reads and writes Apple Reminders through EventKit.
///
/// Writes go to the Mac's Reminders store; iCloud (or the list's account) syncs them to
/// iPhone and iPad. All access runs on the shared hub queue, and `EKReminder`s are
/// converted to `Reminder` values before leaving it.
final class EventKitRemindersRepository: RemindersRepository, @unchecked Sendable {
    private let hub: EventStoreHub
    private var store: EKEventStore { hub.store }
    private var queue: DispatchQueue { hub.queue }

    init(hub: EventStoreHub) {
        self.hub = hub
    }

    func authorizationState() -> CalendarAuthState {
        switch EKEventStore.authorizationStatus(for: .reminder) {
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
            _ = try await store.requestFullAccessToReminders()
        } catch {
            Log.reminders.error("Reminders access request failed: \(error.localizedDescription, privacy: .public)")
        }
        return authorizationState()
    }

    func lists() async -> [ReminderList] {
        await onQueue {
            self.store.calendars(for: .reminder).map(Self.makeList).sorted {
                ($0.accountTitle, $0.title.localizedLowercase) < ($1.accountTitle, $1.title.localizedLowercase)
            }
        }
    }

    func defaultListID() async -> String? {
        await onQueue { self.store.defaultCalendarForNewReminders()?.calendarIdentifier }
    }

    func reminders(listIDs: Set<String>?, completedSince: Date) async -> [Reminder] {
        let started = Date()
        let result: [Reminder] = await withCheckedContinuation { continuation in
            queue.async {
                let all = self.store.calendars(for: .reminder)
                let calendars = listIDs.map { ids in all.filter { ids.contains($0.calendarIdentifier) } } ?? all
                // An empty array would mean "all lists" to EventKit, so bail out explicitly.
                guard !calendars.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }
                let open = self.store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
                let done = self.store.predicateForCompletedReminders(withCompletionDateStarting: completedSince, ending: nil, calendars: calendars)
                self.store.fetchReminders(matching: open) { openItems in
                    let openReminders = (openItems ?? []).map(Self.makeReminder)
                    self.store.fetchReminders(matching: done) { doneItems in
                        continuation.resume(returning: openReminders + (doneItems ?? []).map(Self.makeReminder))
                    }
                }
            }
        }
        Log.reminders.debug("Fetched \(result.count) reminders in \(Date().timeIntervalSince(started), format: .fixed(precision: 3))s")
        return result
    }

    func create(_ edit: ReminderEdit, listID: String?) async throws -> Reminder {
        try await onQueueThrowing {
            let reminder = EKReminder(eventStore: self.store)
            let list = try self.resolveList(listID)
            guard list.allowsContentModifications else { throw RemindersError.readOnlyList }
            reminder.calendar = list
            Self.apply(edit, from: nil, to: reminder)
            try self.save(reminder)
            return Self.makeReminder(reminder)
        }
    }

    func update(id: String, from base: ReminderEdit, to edit: ReminderEdit) async throws -> Reminder {
        try await onQueueThrowing {
            let reminder = try self.reminder(withID: id)
            Self.apply(edit, from: base, to: reminder)
            try self.save(reminder)
            return Self.makeReminder(reminder)
        }
    }

    func setCompleted(id: String, _ completed: Bool) async throws -> Reminder {
        try await onQueueThrowing {
            let reminder = try self.reminder(withID: id)
            // For a repeating reminder, EventKit moves it to the next occurrence on save.
            reminder.isCompleted = completed
            try self.save(reminder)
            return Self.makeReminder(reminder)
        }
    }

    func changes() -> AsyncStream<Void> {
        hub.changes()
    }

    // MARK: - Queue-confined helpers

    private func resolveList(_ listID: String?) throws -> EKCalendar {
        if let listID {
            guard let list = store.calendar(withIdentifier: listID) else { throw RemindersError.notFound }
            return list
        }
        guard let list = store.defaultCalendarForNewReminders() else { throw RemindersError.noDefaultList }
        return list
    }

    private func reminder(withID id: String) throws -> EKReminder {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw RemindersError.notFound
        }
        guard reminder.calendar?.allowsContentModifications ?? false else {
            throw RemindersError.readOnlyList
        }
        // Saving a reminder with a location alert crashes inside EventKit (macOS 27),
        // and the exception can't be caught, so never hand one to save().
        guard !Self.hasLocationAlert(reminder) else {
            throw RemindersError.locationAlert
        }
        return reminder
    }

    private func save(_ reminder: EKReminder) throws {
        do {
            try store.save(reminder, commit: true)
        } catch {
            Log.reminders.error("Saving a reminder failed: \(error.localizedDescription, privacy: .public)")
            throw RemindersError.saveFailed(error.localizedDescription)
        }
    }

    /// Applies only the fields that changed from `base` (all fields when creating).
    private static func apply(_ edit: ReminderEdit, from base: ReminderEdit?, to reminder: EKReminder) {
        if base?.title != edit.title { reminder.title = edit.title }
        if base?.notes != edit.notes { reminder.notes = edit.notes.isEmpty ? nil : edit.notes }
        if base?.priority != edit.priority { reminder.priority = edit.priority.rawValue }
        if base == nil || base?.due != edit.due {
            let previous = base?.due ?? ReminderDue(components: reminder.dueDateComponents)
            reminder.dueDateComponents = edit.due?.components()
            updateDueAlarm(on: reminder, from: previous, to: edit.due)
        }
    }

    /// Mirrors the Reminders app: a reminder with a due time gets an alert at that time.
    /// Only the alert for the old due time is replaced; other alerts are left alone.
    private static func updateDueAlarm(on reminder: EKReminder, from old: ReminderDue?, to new: ReminderDue?) {
        if let old, old.hasTime {
            let oldInstant = old.dueInstant()
            for alarm in reminder.alarms ?? [] where alarm.absoluteDate == oldInstant {
                reminder.removeAlarm(alarm)
            }
        }
        if let new, new.hasTime {
            let instant = new.dueInstant()
            if !(reminder.alarms ?? []).contains(where: { $0.absoluteDate == instant }) {
                reminder.addAlarm(EKAlarm(absoluteDate: instant))
            }
        }
    }

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    private func onQueueThrowing<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    // MARK: - Mapping

    private static func makeList(_ calendar: EKCalendar) -> ReminderList {
        ReminderList(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            accountTitle: calendar.source?.title ?? "Other",
            color: RGBAColor(calendar.color),
            allowsModifications: calendar.allowsContentModifications
        )
    }

    private static func makeReminder(_ reminder: EKReminder) -> Reminder {
        Reminder(
            id: reminder.calendarItemIdentifier,
            listID: reminder.calendar?.calendarIdentifier ?? "",
            listTitle: reminder.calendar?.title ?? "",
            listColor: RGBAColor(reminder.calendar?.color),
            title: reminder.title ?? "",
            notes: reminder.notes ?? "",
            due: ReminderDue(components: reminder.dueDateComponents),
            priority: ReminderPriority(eventKitValue: reminder.priority),
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            creationDate: reminder.creationDate,
            isRecurring: reminder.hasRecurrenceRules,
            hasLocationAlert: hasLocationAlert(reminder)
        )
    }

    private static func hasLocationAlert(_ reminder: EKReminder) -> Bool {
        (reminder.alarms ?? []).contains { $0.structuredLocation != nil || $0.proximity != .none }
    }
}
