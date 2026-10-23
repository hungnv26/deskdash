import XCTest
@testable import DeskDash

final class ReminderDueTests: XCTestCase {
    func testAllDayComponentsRoundTripWithoutTimeZone() {
        let due = ReminderDue(date: TaskDueDate(year: 2026, month: 10, day: 19))
        let components = due.components()
        XCTAssertEqual(components.calendar?.identifier, .gregorian, "EventKit raises unless the calendar is Gregorian")
        XCTAssertNil(components.hour)
        XCTAssertNil(components.timeZone, "All-day reminders float")
        XCTAssertEqual(ReminderDue(components: components), due)
    }

    func testTimedComponentsCarryTimeAndZone() {
        let due = ReminderDue(date: TaskDueDate(year: 2026, month: 10, day: 19), hour: 18, minute: 30)
        let components = due.components(timeZone: TimeZone(identifier: "Australia/Sydney")!)
        XCTAssertEqual(components.hour, 18)
        XCTAssertEqual(components.minute, 30)
        XCTAssertEqual(components.timeZone?.identifier, "Australia/Sydney")
        XCTAssertEqual(ReminderDue(components: components), due)
    }

    func testHourWithoutMinuteDefaultsToZero() {
        XCTAssertEqual(ReminderDue(date: TaskDueDate(year: 2026, month: 1, day: 1), hour: 9).minute, 0)
        XCTAssertNil(ReminderDue(date: TaskDueDate(year: 2026, month: 1, day: 1), minute: 15).minute, "No time means no minute")
    }

    func testDueInstantUsesLocalTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let due = ReminderDue(date: TaskDueDate(year: 2026, month: 10, day: 19), hour: 7, minute: 15)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: due.dueInstant(calendar: calendar))
        XCTAssertEqual(parts, DateComponents(year: 2026, month: 10, day: 19, hour: 7, minute: 15))
    }

    func testPriorityMapping() {
        XCTAssertEqual(ReminderPriority(eventKitValue: 0), .none)
        XCTAssertEqual(ReminderPriority(eventKitValue: 1), .high)
        XCTAssertEqual(ReminderPriority(eventKitValue: 4), .high)
        XCTAssertEqual(ReminderPriority(eventKitValue: 5), .medium)
        XCTAssertEqual(ReminderPriority(eventKitValue: 9), .low)
    }
}

final class ReminderGrouperTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        return calendar
    }()

    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12))! }
    private var today: TaskDueDate { TaskDueDate(year: 2026, month: 10, day: 19) }

    private func reminder(_ title: String, _ due: ReminderDue?, done: Bool = false, priority: ReminderPriority = .none, created: TimeInterval = 0) -> Reminder {
        Reminder(id: title, listID: "l", title: title, due: due, priority: priority, isCompleted: done,
                 completionDate: done ? now : nil, creationDate: Date(timeIntervalSince1970: created))
    }

    private func group(_ reminders: [Reminder], keep: Set<String> = [], completed: Bool = false) -> [ReminderSection: [String]] {
        let groups = ReminderGrouper.group(reminders, now: now, calendar: calendar, keepInPlace: keep, showCompleted: completed)
        return Dictionary(uniqueKeysWithValues: groups.map { ($0.section, $0.reminders.map(\.title)) })
    }

    func testSections() {
        let map = group([
            reminder("yesterday", ReminderDue(date: today.adding(days: -1))),
            reminder("this morning", ReminderDue(date: today, hour: 9)),
            reminder("today", ReminderDue(date: today)),
            reminder("tonight", ReminderDue(date: today, hour: 20)),
            reminder("in a week", ReminderDue(date: today.adding(days: 7))),
            reminder("in 8 days", ReminderDue(date: today.adding(days: 8))),
            reminder("someday", nil),
            reminder("done", ReminderDue(date: today), done: true),
        ])
        XCTAssertEqual(map[.overdue], ["yesterday", "this morning"], "A time today that has passed is overdue")
        XCTAssertEqual(map[.today], ["today", "tonight"], "All-day first, then by time")
        XCTAssertEqual(map[.upcoming], ["in a week"])
        XCTAssertEqual(map[.later], ["in 8 days"])
        XCTAssertEqual(map[.noDueDate], ["someday"])
        XCTAssertNil(map[.completed])
    }

    func testCompletedShownWhenEnabledAndKeptInPlaceWhenRecent() {
        let done = reminder("done", ReminderDue(date: today), done: true)
        XCTAssertEqual(group([done], completed: true)[.completed], ["done"])
        XCTAssertEqual(group([done], keep: ["done"])[.today], ["done"])
    }

    func testPriorityThenCreationOrdering() {
        let map = group([
            reminder("low", nil, priority: .low, created: 1),
            reminder("plain-old", nil, created: 0),
            reminder("high", nil, priority: .high, created: 5),
            reminder("plain-new", nil, created: 9),
        ])
        XCTAssertEqual(map[.noDueDate], ["high", "low", "plain-old", "plain-new"])
    }

    func testDueLabels() {
        XCTAssertNil(DueLabel.text(for: ReminderDue(date: today), section: .today, now: now, calendar: calendar))
        XCTAssertEqual(DueLabel.dayText(for: today.adding(days: 1), today: today, calendar: calendar), "Tomorrow")
        XCTAssertEqual(DueLabel.dayText(for: today.adding(days: -1), today: today, calendar: calendar), "Yesterday")
        XCTAssertTrue(DueLabel.text(for: ReminderDue(date: today.adding(days: 1), hour: 9), section: .upcoming, now: now, calendar: calendar)!.hasPrefix("Tomorrow, "))
    }
}

@MainActor
final class RemindersStoreTests: XCTestCase {
    private var repository: MockRemindersRepository!
    private var defaults: UserDefaults!
    private var store: RemindersStore!

    override func setUp() async throws {
        let lists = [
            ReminderList(id: "home", title: "Home", accountTitle: "iCloud"),
            ReminderList(id: "work", title: "Work", accountTitle: "iCloud"),
            ReminderList(id: "shared", title: "Shared", accountTitle: "Exchange", allowsModifications: false),
        ]
        repository = MockRemindersRepository(lists: lists, reminders: [
            Reminder(id: "a", listID: "home", listTitle: "Home", title: "Alpha", due: ReminderDue(date: .today())),
            Reminder(id: "b", listID: "work", listTitle: "Work", title: "Bravo", notes: "n"),
            Reminder(id: "c", listID: "shared", listTitle: "Shared", title: "Read-only"),
            Reminder(id: "old", listID: "home", listTitle: "Home", title: "Done long ago", isCompleted: true, completionDate: Date(timeIntervalSinceNow: -60 * 24 * 3600)),
        ])
        defaults = UserDefaults(suiteName: "DeskDashTests-\(UUID().uuidString)")!
        store = RemindersStore(repository: repository, preferences: PreferencesStore(defaults: defaults))
        await store.reload()
    }

    func testLoadsAllListsAndSkipsOldCompleted() {
        XCTAssertEqual(store.authState, .granted)
        XCTAssertEqual(Set(store.reminders.map(\.id)), ["a", "b", "c"])
        XCTAssertEqual(store.lists.count, 3)
        XCTAssertEqual(store.listForNewReminders?.id, "home", "Default list")
    }

    func testSelectingAListFiltersAndTargetsIt() async {
        store.selectList("work")
        await store.reload()
        XCTAssertEqual(store.reminders.map(\.id), ["b"])
        XCTAssertEqual(store.listForNewReminders?.id, "work")
    }

    func testMissingSelectedListFallsBackToAllWithNotice() async {
        store.selectList("gone")
        await store.reload()
        XCTAssertNil(store.selectedListID)
        XCTAssertNotNil(store.notice)
        XCTAssertEqual(store.reminders.count, 3)
    }

    func testCompleteWritesThrough() async {
        store.setCompleted("a", true)
        XCTAssertTrue(store.reminder("a")!.isCompleted, "Optimistic")
        XCTAssertTrue(store.pending.contains("a"))
        await store.waitUntilIdle()
        XCTAssertTrue(repository.reminder("a")!.isCompleted)
        XCTAssertFalse(store.pending.contains("a"))
        XCTAssertEqual(store.groups().first { $0.section == .today }?.reminders.map(\.id), ["a"], "Stays in place right after completing")
    }

    func testRapidToggleEndsWhereTheUserLeftIt() async {
        store.setCompleted("a", true)
        store.setCompleted("a", false)
        store.setCompleted("a", true)
        await store.waitUntilIdle()
        XCTAssertEqual(repository.reminder("a")?.isCompleted, true)
        XCTAssertEqual(store.reminder("a")?.isCompleted, true)
        XCTAssertEqual(repository.count(.complete), 3, "Writes run one at a time, in order")
    }

    func testFailedCompleteRollsBackAndRetryWorks() async {
        repository.failNext(.complete, with: .saveFailed("disk full"))
        store.setCompleted("a", true)
        await store.waitUntilIdle()
        XCTAssertEqual(store.reminder("a")?.isCompleted, false)
        XCTAssertEqual(store.banner?.retry, .complete(id: "a", completed: true))

        store.handleRetry(store.banner!.retry!)
        await store.waitUntilIdle()
        XCTAssertEqual(store.reminder("a")?.isCompleted, true)
        XCTAssertNil(store.banner)
    }

    func testEditOnlyWritesChangedFields() async {
        // Another device changes the notes; we change the title. Both must survive.
        repository.externalChange { reminders in
            reminders[reminders.firstIndex { $0.id == "b" }!].notes = "edited on iPhone"
        }
        var edit = store.reminder("b")!.edit
        edit.title = "Bravo renamed"
        edit.priority = .high
        store.save("b", edit: edit)
        await store.waitUntilIdle()
        let saved = repository.reminder("b")!
        XCTAssertEqual(saved.title, "Bravo renamed")
        XCTAssertEqual(saved.priority, .high)
        XCTAssertEqual(saved.notes, "edited on iPhone")
    }

    func testBlankEditIsIgnored() async {
        var edit = store.reminder("b")!.edit
        edit.title = "   "
        store.save("b", edit: edit)
        await store.waitUntilIdle()
        XCTAssertEqual(repository.count(.update), 0)
    }

    func testCreateShowsPlaceholderThenSavedReminder() async {
        XCTAssertTrue(store.create(title: "  Buy milk ", due: ReminderDue(date: .today(), hour: 18)))
        let placeholder = store.reminders.first { $0.title == "Buy milk" }
        XCTAssertTrue(placeholder!.id.hasPrefix(RemindersStore.placeholderPrefix))
        XCTAssertFalse(store.isEditable(placeholder!), "Can't edit until saved")
        await store.waitUntilIdle()
        let rows = store.reminders.filter { $0.title == "Buy milk" }
        XCTAssertEqual(rows.count, 1)
        XCTAssertFalse(rows[0].id.hasPrefix(RemindersStore.placeholderPrefix))
        XCTAssertEqual(rows[0].listID, "home")
        XCTAssertEqual(rows[0].due?.hour, 18)
    }

    func testFailedCreateKeepsTextForRetry() async {
        repository.failNext(.create, with: .saveFailed("offline"))
        store.create(title: "Call Mum")
        await store.waitUntilIdle()
        XCTAssertFalse(store.reminders.contains { $0.title == "Call Mum" })
        guard case .create(let edit, let listID)? = store.banner?.retry else { return XCTFail("Expected a create retry") }
        XCTAssertEqual(edit.title, "Call Mum")
        store.handleRetry(.create(edit: edit, listID: listID))
        await store.waitUntilIdle()
        XCTAssertEqual(store.reminders.filter { $0.title == "Call Mum" }.count, 1)
    }

    func testReadOnlyListCannotBeChanged() async {
        XCTAssertFalse(store.isEditable(store.reminder("c")!))
        store.setCompleted("c", true)
        await store.waitUntilIdle()
        XCTAssertEqual(repository.count(.complete), 0)
        store.selectList("shared")
        await store.reload()
        XCTAssertFalse(store.create(title: "Nope"))
        XCTAssertEqual(store.banner?.message, RemindersError.readOnlyList.userMessage)
    }

    func testReminderDeletedElsewhereIsRemovedOnWrite() async {
        repository.externalChange { $0.removeAll { $0.id == "b" } }
        store.setCompleted("b", true)
        await store.waitUntilIdle()
        XCTAssertNil(store.reminder("b"))
        XCTAssertEqual(store.banner?.message, RemindersError.notFound.userMessage)
    }

    func testExternalChangeTriggersReload() async throws {
        store.start()
        try await Task.sleep(for: .milliseconds(100))
        repository.externalChange { $0.append(Reminder(id: "new", listID: "home", title: "From iPhone")) }
        for _ in 0..<40 where store.reminder("new") == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(store.reminder("new")?.title, "From iPhone")
    }

    func testAccessDeniedShowsNothing() async {
        let denied = RemindersStore(
            repository: MockRemindersRepository(state: .denied, lists: [], reminders: []),
            preferences: PreferencesStore(defaults: defaults)
        )
        await denied.reload()
        XCTAssertEqual(denied.authState, .denied)
        XCTAssertTrue(denied.reminders.isEmpty)
        XCTAssertFalse(denied.create(title: "x"))
    }
}

@MainActor
final class LocationAlertTests: XCTestCase {
    /// EventKit crashes when saving a reminder with a location alert (macOS 27), so the
    /// store must never send one to the repository.
    func testLocationAlertRemindersAreNeverWritten() async {
        let repository = MockRemindersRepository(
            lists: [ReminderList(id: "home", title: "Home", accountTitle: "iCloud")],
            reminders: [Reminder(id: "loc", listID: "home", title: "Call back", hasLocationAlert: true)]
        )
        let store = RemindersStore(repository: repository, preferences: PreferencesStore(defaults: UserDefaults(suiteName: "DeskDashTests-\(UUID().uuidString)")!))
        await store.reload()
        let reminder = store.reminder("loc")!
        XCTAssertFalse(store.isEditable(reminder))

        store.setCompleted("loc", true)
        var edit = reminder.edit
        edit.title = "Changed"
        store.save("loc", edit: edit)
        await store.waitUntilIdle()

        XCTAssertEqual(repository.count(.complete), 0)
        XCTAssertEqual(repository.count(.update), 0)
        XCTAssertEqual(store.reminder("loc")?.isCompleted, false)
        XCTAssertEqual(store.reminder("loc")?.title, "Call back")
    }
}
