import Foundation

/// In-memory Reminders stand-in for demo mode and tests, with failure injection.
final class MockRemindersRepository: RemindersRepository, @unchecked Sendable {
    enum Operation: Hashable, Sendable {
        case create, update, complete
    }

    private let lock = NSLock()
    private var state: CalendarAuthState
    private var storedLists: [ReminderList]
    private var stored: [Reminder]
    private var failures: [Operation: [RemindersError]] = [:]
    private var counts: [Operation: Int] = [:]
    private var nextID = 1
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private let latency: Duration

    init(state: CalendarAuthState = .granted, lists: [ReminderList], reminders: [Reminder], latency: Duration = .zero) {
        self.state = state
        self.storedLists = lists
        self.stored = reminders
        self.latency = latency
    }

    // MARK: - Test controls

    func failNext(_ operation: Operation, with error: RemindersError) {
        lock.withLock { failures[operation, default: []].append(error) }
    }

    func count(_ operation: Operation) -> Int { lock.withLock { counts[operation] ?? 0 } }

    func reminder(_ id: String) -> Reminder? { lock.withLock { stored.first { $0.id == id } } }

    var allReminders: [Reminder] { lock.withLock { stored } }

    /// Simulates a change synced in from another device.
    func externalChange(_ change: (inout [Reminder]) -> Void) {
        let streams = lock.withLock {
            change(&stored)
            return Array(continuations.values)
        }
        streams.forEach { $0.yield() }
    }

    // MARK: - RemindersRepository

    func authorizationState() -> CalendarAuthState { lock.withLock { state } }

    func requestAccess() async -> CalendarAuthState {
        lock.withLock {
            if state == .notDetermined { state = .granted }
            return state
        }
    }

    func lists() async -> [ReminderList] {
        lock.withLock { state == .granted ? storedLists : [] }
    }

    func defaultListID() async -> String? {
        lock.withLock { storedLists.first(where: \.allowsModifications)?.id }
    }

    func reminders(listIDs: Set<String>?, completedSince: Date) async -> [Reminder] {
        lock.withLock {
            guard state == .granted else { return [] }
            return stored.filter { reminder in
                guard listIDs?.contains(reminder.listID) ?? true else { return false }
                return !reminder.isCompleted || (reminder.completionDate ?? .distantPast) >= completedSince
            }
        }
    }

    func create(_ edit: ReminderEdit, listID: String?) async throws -> Reminder {
        try await begin(.create)
        return try lock.withLock {
            let id = listID ?? storedLists.first(where: \.allowsModifications)?.id
            guard let list = storedLists.first(where: { $0.id == id }) else { throw RemindersError.noDefaultList }
            guard list.allowsModifications else { throw RemindersError.readOnlyList }
            nextID += 1
            var reminder = Reminder(id: "mock-\(nextID)", listID: list.id, listTitle: list.title, listColor: list.color, title: edit.title, creationDate: Date())
            reminder.edit = edit
            stored.append(reminder)
            return reminder
        }
    }

    func update(id: String, from base: ReminderEdit, to edit: ReminderEdit) async throws -> Reminder {
        try await begin(.update)
        return try lock.withLock {
            let index = try writableIndex(id)
            var current = stored[index].edit
            if base.title != edit.title { current.title = edit.title }
            if base.notes != edit.notes { current.notes = edit.notes }
            if base.due != edit.due { current.due = edit.due }
            if base.priority != edit.priority { current.priority = edit.priority }
            stored[index].edit = current
            return stored[index]
        }
    }

    func setCompleted(id: String, _ completed: Bool) async throws -> Reminder {
        try await begin(.complete)
        return try lock.withLock {
            let index = try writableIndex(id)
            stored[index].isCompleted = completed
            stored[index].completionDate = completed ? Date() : nil
            return stored[index]
        }
    }

    func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let key = UUID()
            lock.withLock { continuations[key] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { _ = self.continuations.removeValue(forKey: key) }
            }
        }
    }

    // MARK: - Helpers

    private func begin(_ operation: Operation) async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
        let failure: RemindersError? = lock.withLock {
            counts[operation, default: 0] += 1
            guard var queue = failures[operation], !queue.isEmpty else { return nil }
            let error = queue.removeFirst()
            failures[operation] = queue
            return error
        }
        if let failure { throw failure }
    }

    private func writableIndex(_ id: String) throws -> Int {
        guard let index = stored.firstIndex(where: { $0.id == id }) else { throw RemindersError.notFound }
        guard storedLists.first(where: { $0.id == stored[index].listID })?.allowsModifications ?? false else {
            throw RemindersError.readOnlyList
        }
        guard !stored[index].hasLocationAlert else { throw RemindersError.locationAlert }
        return index
    }

    // MARK: - Demo data

    static func demo(now: Date = Date()) -> MockRemindersRepository {
        let today = TaskDueDate.today(now: now)
        let lists = [
            ReminderList(id: "reminders", title: "Reminders", accountTitle: "iCloud", color: RGBAColor(red: 0.20, green: 0.48, blue: 0.96)),
            ReminderList(id: "work", title: "Work", accountTitle: "iCloud", color: RGBAColor(red: 0.96, green: 0.58, blue: 0.16)),
            ReminderList(id: "home", title: "Home", accountTitle: "iCloud", color: RGBAColor(red: 0.20, green: 0.70, blue: 0.40)),
        ]
        func item(_ id: Int, _ list: Int, _ title: String, due: Int?, hour: Int? = nil, notes: String = "",
                  priority: ReminderPriority = .none, done: Bool = false, repeats: Bool = false) -> Reminder {
            let l = lists[list]
            return Reminder(
                id: "demo-\(id)", listID: l.id, listTitle: l.title, listColor: l.color, title: title, notes: notes,
                due: due.map { ReminderDue(date: today.adding(days: $0), hour: hour) }, priority: priority,
                isCompleted: done, completionDate: done ? now.addingTimeInterval(-3600) : nil,
                creationDate: now.addingTimeInterval(TimeInterval(-id * 600)), isRecurring: repeats
            )
        }
        let reminders = [
            item(1, 1, "Send Q4 budget to finance", due: -2, notes: "Include the revised hosting estimate.", priority: .high),
            item(2, 2, "Renew car registration", due: -1),
            item(3, 1, "Review pull request from Linh", due: 0, hour: 10),
            item(4, 1, "Book flights for the summit", due: 0, hour: 16, notes: "Prefer the morning flight."),
            item(5, 0, "Call the dentist to reschedule", due: 0, priority: .medium),
            item(6, 2, "Take out the bins", due: 0, hour: 19, repeats: true),
            item(7, 1, "Draft the monthly client update", due: 2),
            item(8, 2, "Pay electricity bill", due: 4, priority: .high),
            item(9, 1, "Prepare sprint retro notes", due: 6, hour: 9),
            item(10, 0, "Annual insurance review", due: 21),
            item(11, 0, "Read 'Designing Data-Intensive Applications'", due: nil),
            item(12, 2, "Clean up Downloads folder", due: nil, priority: .low),
            item(13, 2, "Water the plants", due: 0, done: true),
        ]
        return MockRemindersRepository(lists: lists, reminders: reminders, latency: .milliseconds(120))
    }
}
