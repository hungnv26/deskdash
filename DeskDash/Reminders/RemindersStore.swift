import AppKit
import Foundation
import Observation

/// Presentation state for the reminders panel.
///
/// Apple Reminders is the source of truth; DeskDash keeps no copy of its own. Changes
/// show immediately, are written to the Mac's Reminders store, and iCloud syncs them to
/// other devices. If a write fails, the row goes back to what it was, a Retry banner
/// appears, and the store is re-read. Writes to the same reminder run one at a time.
@MainActor
@Observable
final class RemindersStore {
    enum RetryAction: Equatable {
        case reload
        case complete(id: String, completed: Bool)
        case edit(id: String, edit: ReminderEdit)
        case create(edit: ReminderEdit, listID: String)
    }

    struct Banner: Equatable, Identifiable {
        let id = UUID()
        var message: String
        var retry: RetryAction?
    }

    private(set) var authState: CalendarAuthState
    private(set) var lists: [ReminderList] = []
    private(set) var reminders: [Reminder] = []
    private(set) var defaultListID: String?
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    /// Reminders with a write in flight.
    private(set) var pending: Set<String> = []
    private(set) var banner: Banner?
    /// Explains a selected list that disappeared. Dismissible.
    var notice: String?
    /// Reminders just completed here keep their place briefly instead of vanishing.
    private(set) var keepInPlace: [String: Date] = [:]

    @ObservationIgnored private let repository: RemindersRepository
    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var chains: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var started = false

    @ObservationIgnored var keepInPlaceDuration: TimeInterval = 45
    @ObservationIgnored var completedWindow: TimeInterval = 14 * 24 * 3600

    static let placeholderPrefix = "pending-"

    init(repository: RemindersRepository, preferences: PreferencesStore, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.preferences = preferences
        self.now = now
        self.authState = repository.authorizationState()
    }

    // MARK: - Derived state

    /// `nil` means all lists.
    var selectedListID: String? { preferences.selectedReminderListID }

    var selectedList: ReminderList? {
        lists.first { $0.id == selectedListID }
    }

    /// Where quick-add puts new reminders: the selected list, or the Reminders default list.
    var listForNewReminders: ReminderList? {
        let id = selectedListID ?? defaultListID
        return lists.first { $0.id == id } ?? lists.first(where: \.allowsModifications)
    }

    func groups(now: Date = Date()) -> [ReminderGroup] {
        ReminderGrouper.group(
            reminders,
            now: now,
            keepInPlace: Set(keepInPlace.keys),
            showCompleted: preferences.showCompletedReminders
        )
    }

    func reminder(_ id: String) -> Reminder? {
        reminders.first { $0.id == id }
    }

    func list(_ id: String) -> ReminderList? {
        lists.first { $0.id == id }
    }

    func isEditable(_ reminder: Reminder) -> Bool {
        !reminder.id.hasPrefix(Self.placeholderPrefix)
            && !reminder.hasLocationAlert
            && (list(reminder.listID)?.allowsModifications ?? true)
    }

    /// For reminders DeskDash can't change: explain why and open the Reminders app.
    func openInRemindersApp(_ reminder: Reminder) {
        if reminder.hasLocationAlert {
            banner = Banner(message: RemindersError.locationAlert.userMessage, retry: nil)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app"))
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        let stream = repository.changes()
        changeTask = Task { [weak self] in
            for await _ in stream {
                self?.scheduleReload(debounce: .milliseconds(500))
            }
        }
        let center = NotificationCenter.default
        let reload: @MainActor () -> Void = { [weak self] in self?.scheduleReload(debounce: .milliseconds(300)) }
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { reload() }
        })
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { reload() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { reload() }
        })
        Task { await self.reload() }
    }

    func requestAccess() async {
        authState = await repository.requestAccess()
        await reload()
    }

    func selectList(_ id: String?) {
        guard id != selectedListID else { return }
        preferences.selectedReminderListID = id
        reminders = reminders.filter { $0.id.hasPrefix(Self.placeholderPrefix) }
        hasLoaded = false
        scheduleReload()
    }

    func dismissBanner() { banner = nil }

    func handleRetry(_ action: RetryAction) {
        banner = nil
        switch action {
        case .reload: scheduleReload()
        case let .complete(id, completed): setCompleted(id, completed)
        case let .edit(id, edit): save(id, edit: edit)
        case let .create(edit, listID): create(edit, listID: listID)
        }
    }

    // MARK: - Loading

    func scheduleReload(debounce: Duration = .zero) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            if debounce > .zero {
                try? await Task.sleep(for: debounce)
                guard !Task.isCancelled else { return }
            }
            await self?.reload()
        }
    }

    func reload() async {
        authState = repository.authorizationState()
        guard authState == .granted else {
            lists = []
            reminders = []
            hasLoaded = true
            return
        }
        isLoading = true
        defer { isLoading = false }

        lists = await repository.lists()
        defaultListID = await repository.defaultListID()
        if let selected = selectedListID, !lists.isEmpty, !lists.contains(where: { $0.id == selected }) {
            preferences.selectedReminderListID = nil
            notice = "The list you had selected is no longer in Reminders, so DeskDash is showing all lists."
        }

        let listFilter = selectedListID.map { Set([$0]) }
        let fetched = await repository.reminders(listIDs: listFilter, completedSince: now().addingTimeInterval(-completedWindow))
        guard listFilter == selectedListID.map({ Set([$0]) }) else { return }

        // Rows with a write in flight keep their optimistic values until the write answers.
        let local = Dictionary(reminders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var merged = fetched.map { pending.contains($0.id) ? (local[$0.id] ?? $0) : $0 }
        merged += reminders.filter { $0.id.hasPrefix(Self.placeholderPrefix) }
        reminders = merged
        pruneKeepInPlace()
        hasLoaded = true
        if banner?.retry == .reload { banner = nil }
    }

    // MARK: - Mutations

    func setCompleted(_ id: String, _ completed: Bool) {
        guard let index = index(of: id), isEditable(reminders[index]) else { return }
        let before = reminders[index]
        keepInPlace[id] = now()
        reminders[index].isCompleted = completed
        reminders[index].completionDate = completed ? now() : nil
        enqueue(id) { store in
            do {
                store.apply(try await store.repository.setCompleted(id: id, completed))
            } catch {
                store.fail(id, restoring: before, error: error, retry: .complete(id: id, completed: completed))
            }
        }
    }

    func save(_ id: String, edit: ReminderEdit) {
        var edit = edit
        edit.title = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !edit.title.isEmpty, let index = index(of: id), isEditable(reminders[index]) else { return }
        let before = reminders[index]
        guard edit != before.edit else { return }
        reminders[index].edit = edit
        enqueue(id) { store in
            do {
                store.apply(try await store.repository.update(id: id, from: before.edit, to: edit))
            } catch {
                store.fail(id, restoring: before, error: error, retry: .edit(id: id, edit: edit))
            }
        }
    }

    /// Adds a reminder to the selected list (or the default list). Returns false if there's nothing to add.
    @discardableResult
    func create(title: String, due: ReminderDue? = nil) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let list = listForNewReminders else { return false }
        guard list.allowsModifications else {
            banner = Banner(message: RemindersError.readOnlyList.userMessage, retry: nil)
            return false
        }
        create(ReminderEdit(title: trimmed, notes: "", due: due, priority: .none), listID: list.id)
        return true
    }

    private func create(_ edit: ReminderEdit, listID: String) {
        guard authState == .granted else { return }
        let list = list(listID)
        let placeholderID = Self.placeholderPrefix + UUID().uuidString
        var placeholder = Reminder(id: placeholderID, listID: listID, listTitle: list?.title ?? "", listColor: list?.color, title: edit.title, creationDate: now())
        placeholder.edit = edit
        reminders.append(placeholder)
        pending.insert(placeholderID)

        Task {
            defer { pending.remove(placeholderID) }
            do {
                let saved = try await repository.create(edit, listID: listID)
                reminders.removeAll { $0.id == placeholderID }
                apply(saved)
            } catch {
                reminders.removeAll { $0.id == placeholderID }
                let reason = RemindersError.from(error).userMessage
                banner = Banner(message: "Couldn't add “\(edit.title)”. \(reason)", retry: .create(edit: edit, listID: listID))
                Log.reminders.error("Creating a reminder failed")
            }
        }
    }

    /// Runs writes for one reminder strictly in order.
    private func enqueue(_ id: String, _ work: @escaping @MainActor (RemindersStore) async -> Void) {
        let previous = chains[id]
        pending.insert(id)
        let task = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await work(self)
        }
        chains[id] = task
        Task { [weak self] in
            await task.value
            guard let self, self.chains[id] == task else { return }
            self.chains[id] = nil
            self.pending.remove(id)
        }
    }

    private func apply(_ saved: Reminder) {
        if let index = index(of: saved.id) {
            reminders[index] = saved
        } else {
            reminders.append(saved)
        }
    }

    private func fail(_ id: String, restoring before: Reminder, error: Error, retry: RetryAction) {
        let failure = RemindersError.from(error)
        if failure == .notFound {
            reminders.removeAll { $0.id == id }
            banner = Banner(message: failure.userMessage, retry: nil)
        } else {
            if let index = index(of: id) { reminders[index] = before }
            banner = Banner(message: failure.userMessage, retry: retry)
        }
        Log.reminders.error("A reminder change failed and was rolled back")
        scheduleReload(debounce: .milliseconds(200))
    }

    // MARK: - Helpers

    private func index(of id: String) -> Int? {
        reminders.firstIndex { $0.id == id }
    }

    private func pruneKeepInPlace() {
        let cutoff = now().addingTimeInterval(-keepInPlaceDuration)
        keepInPlace = keepInPlace.filter { id, date in date > cutoff || pending.contains(id) }
    }

    /// Waits until no write is in flight. For tests.
    func waitUntilIdle() async {
        while let task = chains.values.first {
            await task.value
            await Task.yield()
        }
        while !pending.isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        }
        if let reloadTask { await reloadTask.value }
    }
}

extension RemindersError {
    static func from(_ error: Error) -> RemindersError {
        (error as? RemindersError) ?? .saveFailed(error.localizedDescription)
    }
}
