import Foundation

/// Reminder operations. Views and stores only see this protocol. No deletes.
protocol RemindersRepository: AnyObject, Sendable {
    func authorizationState() -> CalendarAuthState
    /// Asks for access. Only call from an explicit user action.
    func requestAccess() async -> CalendarAuthState
    func lists() async -> [ReminderList]
    /// The list new reminders go to by default (set in the Reminders app).
    func defaultListID() async -> String?
    /// Incomplete reminders, plus reminders completed since `completedSince`.
    /// `listIDs == nil` means every list.
    func reminders(listIDs: Set<String>?, completedSince: Date) async -> [Reminder]
    func create(_ edit: ReminderEdit, listID: String?) async throws -> Reminder
    /// Writes only the fields that differ between `base` and `edit`, so a change made on
    /// another device to a different field is never overwritten.
    func update(id: String, from base: ReminderEdit, to edit: ReminderEdit) async throws -> Reminder
    func setCompleted(id: String, _ completed: Bool) async throws -> Reminder
    func changes() -> AsyncStream<Void>
}
