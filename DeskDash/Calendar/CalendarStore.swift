import AppKit
import Foundation
import Observation

/// Presentation state for the calendar panel.
@MainActor
@Observable
final class CalendarStore {
    private(set) var authState: CalendarAuthState
    private(set) var calendars: [CalendarSource] = []
    private(set) var events: [CalendarEvent] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// Explains calendars that disappeared from the selection. Dismissible.
    var notice: String?

    /// The day whose agenda is shown.
    private(set) var selectedDate: Date
    /// The first day of the month shown in the month grid.
    private(set) var displayedMonth: Date
    /// Bumped when the date changes at midnight so "today" highlights refresh.
    private(set) var today: Date
    private(set) var defaultCalendarID: String?
    /// Incremented to ask the calendar panel to open the new-event editor.
    var newEventRequest = 0

    @ObservationIgnored private let repository: CalendarRepository
    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var started = false

    var math: CalendarMath { CalendarMath(calendar: .autoupdatingCurrent) }

    init(repository: CalendarRepository, preferences: PreferencesStore, now: Date = Date()) {
        self.repository = repository
        self.preferences = preferences
        self.authState = repository.authorizationState()
        let math = CalendarMath(calendar: .autoupdatingCurrent)
        self.selectedDate = math.startOfDay(now)
        self.displayedMonth = math.startOfMonth(now)
        self.today = math.startOfDay(now)
    }

    var viewMode: CalendarViewMode {
        get { preferences.calendarViewMode }
        set { preferences.calendarViewMode = newValue }
    }

    var visibleCalendarIDs: Set<String>? { preferences.selectedCalendarIDs }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        let stream = repository.changes()
        changeTask = Task { [weak self] in
            for await _ in stream {
                self?.scheduleReload(debounce: .seconds(1))
            }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleDayChange() }
        })
        observers.append(center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleDayChange() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReload(debounce: .milliseconds(300)) }
        })
        Task { await reload() }
    }

    // MARK: - Access

    func requestAccess() async {
        authState = await repository.requestAccess()
        await reload()
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
            calendars = []
            events = []
            hasLoaded = true
            return
        }
        isLoading = true
        defer { isLoading = false }

        calendars = await repository.calendars()
        defaultCalendarID = await repository.defaultCalendarID()
        pruneMissingCalendars()

        let interval = queryInterval()
        events = await repository.events(in: interval, calendarIDs: visibleCalendarIDs)
        hasLoaded = true
    }

    /// Month grid (including adjacent-month days it shows) plus the selected day.
    private func queryInterval() -> DateInterval {
        let grid = math.gridInterval(for: displayedMonth)
        let day = math.dayInterval(containing: selectedDate)
        return DateInterval(start: min(grid.start, day.start), end: max(grid.end, day.end))
    }

    private func pruneMissingCalendars() {
        guard let selected = preferences.selectedCalendarIDs, !calendars.isEmpty else { return }
        let available = Set(calendars.map(\.id))
        let missing = selected.subtracting(available)
        guard !missing.isEmpty else { return }
        preferences.selectedCalendarIDs = selected.intersection(available)
        notice = missing.count == 1
            ? "A calendar you had selected is no longer available in macOS Calendar and was removed."
            : "\(missing.count) calendars you had selected are no longer available in macOS Calendar and were removed."
    }

    // MARK: - Calendar visibility

    func isVisible(_ calendar: CalendarSource) -> Bool {
        visibleCalendarIDs?.contains(calendar.id) ?? true
    }

    func setVisible(_ visible: Bool, calendar: CalendarSource) {
        var selected = visibleCalendarIDs ?? Set(calendars.map(\.id))
        if visible { selected.insert(calendar.id) } else { selected.remove(calendar.id) }
        preferences.selectedCalendarIDs = selected.count == calendars.count ? nil : selected
        scheduleReload()
    }

    // MARK: - Navigation

    func select(_ date: Date) {
        let day = math.startOfDay(date)
        selectedDate = day
        if !math.isSameMonth(day, displayedMonth) {
            displayedMonth = math.startOfMonth(day)
        }
        scheduleReload()
    }

    func goToToday() {
        today = math.startOfDay(Date())
        select(today)
    }

    /// Moves one day or one month, depending on the view.
    func step(_ direction: Int) {
        let calendar = math.calendar
        switch viewMode {
        case .day:
            if let next = calendar.date(byAdding: .day, value: direction, to: selectedDate) { select(next) }
        case .month:
            // Keeps the same day number, clamped to the new month's length.
            if let next = calendar.date(byAdding: .month, value: direction, to: selectedDate) { select(next) }
        }
    }

    private func handleDayChange() {
        let wasToday = math.isSameDay(selectedDate, today)
        today = math.startOfDay(Date())
        if wasToday { select(today) } else { scheduleReload() }
    }

    // MARK: - Writes

    /// Calendars that accept new and edited events.
    var writableCalendars: [CalendarSource] {
        calendars.filter(\.allowsModifications)
    }

    /// Where new events go: the Calendar app's default if writable, otherwise the first writable calendar.
    var calendarForNewEvents: CalendarSource? {
        writableCalendars.first { $0.id == defaultCalendarID } ?? writableCalendars.first
    }

    func newEventDraft(on day: Date? = nil) -> EventDraft? {
        guard let calendar = calendarForNewEvents else { return nil }
        return EventDraft.new(on: day ?? selectedDate, calendarID: calendar.id)
    }

    /// Saves a new event. Returns an error message for the editor, or nil on success.
    func createEvent(_ draft: EventDraft) async -> String? {
        do {
            let saved = try await repository.createEvent(draft)
            noteIfHidden(saved)
            select(saved.startDate)
            await reload()
            return nil
        } catch {
            return CalendarWriteError.from(error).userMessage
        }
    }

    /// Saves changes to an event. Returns an error message for the editor, or nil on success.
    func updateEvent(_ event: CalendarEvent, from base: EventDraft, to draft: EventDraft, span: EventSpan) async -> String? {
        do {
            let saved = try await repository.updateEvent(event, from: base, to: draft, span: span)
            noteIfHidden(saved)
            await reload()
            return nil
        } catch {
            let failure = CalendarWriteError.from(error)
            if failure == .notFound { scheduleReload() }
            return failure.userMessage
        }
    }

    private func noteIfHidden(_ event: CalendarEvent) {
        if let visible = visibleCalendarIDs, !visible.contains(event.calendarID) {
            notice = "Saved to “\(event.calendarTitle)”, which is hidden. Show it in Settings › Calendars."
        }
    }

    // MARK: - Derived data

    var selectedAgenda: (allDay: [CalendarEvent], timed: [CalendarEvent]) {
        math.agenda(for: selectedDate, from: events)
    }

    var gridDays: [Date] { math.monthGridDays(for: displayedMonth) }

    var eventsByDay: [Date: [CalendarEvent]] { math.eventsByDay(events, days: gridDays) }

    func calendar(withID id: String) -> CalendarSource? {
        calendars.first { $0.id == id }
    }
}
