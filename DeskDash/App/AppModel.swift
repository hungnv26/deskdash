import AppKit
import Observation
import SwiftUI

/// Transient UI requests shared between menus and views.
@MainActor
@Observable
final class DashboardUIState {
    /// Incremented to ask the quick-add field to take focus.
    var quickAddFocusRequest = 0
    /// Whether the pointer is over the dashboard window.
    var pointerInside = false
}

/// Wires the app together: preferences, stores, repositories and windows.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let isDemo: Bool
    let preferences: PreferencesStore
    let calendar: CalendarStore
    let reminders: RemindersStore
    let ui = DashboardUIState()
    private(set) var windows: DashboardWindowController!
    private var statusItem: StatusItemController?
    private var launched = false
    /// Captured from the SwiftUI environment so AppKit menus can open Settings.
    var openSettingsAction: (() -> Void)?

    private init() {
        let defaults = UserDefaults.standard
        isDemo = defaults.bool(forKey: "DemoMode")
        preferences = PreferencesStore(defaults: isDemo ? (UserDefaults(suiteName: "net.hungngo.DeskDash.demo") ?? defaults) : defaults)

        let calendarRepository: CalendarRepository
        let remindersRepository: RemindersRepository
        if isDemo {
            calendarRepository = MockCalendarRepository()
            remindersRepository = MockRemindersRepository.demo()
        } else {
            // One EKEventStore for both calendar and reminders.
            let hub = EventStoreHub()
            calendarRepository = EventKitCalendarRepository(hub: hub)
            remindersRepository = EventKitRemindersRepository(hub: hub)
        }

        calendar = CalendarStore(repository: calendarRepository, preferences: preferences)
        reminders = RemindersStore(repository: remindersRepository, preferences: preferences)
        windows = DashboardWindowController(preferences: preferences) { [unowned self] mode in
            self.rootView(for: mode)
        }
    }

    func launch() {
        guard !launched else { return }
        launched = true
        Log.app.info("Launching DeskDash (demo: \(self.isDemo, privacy: .public))")
        applyAppearance()
        statusItem = StatusItemController(model: self)
        windows.show()
        calendar.start()
        reminders.start()
    }

    private func rootView(for mode: WindowMode) -> AnyView {
        AnyView(
            DashboardRootView(mode: mode)
                .environment(preferences)
                .environment(calendar)
                .environment(reminders)
                .environment(ui)
                .environment(\.dashboardActions, actions)
        )
    }

    var actions: DashboardActions {
        DashboardActions(
            toggleMode: { [unowned self] in self.windows.toggleMode() },
            refresh: { [unowned self] in self.refreshAll() },
            newTask: { [unowned self] in self.newTask() }
        )
    }

    // MARK: - Commands

    func refreshAll() {
        calendar.scheduleReload()
        reminders.scheduleReload()
    }

    func newTask() {
        windows.focus()
        ui.quickAddFocusRequest += 1
    }

    func newEvent() {
        windows.focus()
        calendar.newEventRequest += 1
    }

    func showDashboard() {
        windows.show()
        if preferences.windowMode == .desktop { windows.focus() }
    }

    func setMode(_ mode: WindowMode) {
        windows.setMode(mode)
    }

    func showSettings() {
        NSApp.activate()
        if let openSettingsAction {
            openSettingsAction()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    func applyAppearance() {
        NSApp.appearance = preferences.appearance.nsAppearance
    }
}

/// Actions views can trigger without knowing about windows or the app model.
struct DashboardActions: Sendable {
    var toggleMode: @MainActor @Sendable () -> Void = {}
    var refresh: @MainActor @Sendable () -> Void = {}
    var newTask: @MainActor @Sendable () -> Void = {}
}

private struct DashboardActionsKey: EnvironmentKey {
    static let defaultValue = DashboardActions()
}

extension EnvironmentValues {
    var dashboardActions: DashboardActions {
        get { self[DashboardActionsKey.self] }
        set { self[DashboardActionsKey.self] = newValue }
    }
}
