import SwiftUI

@main
struct DeskDashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            if AppDelegate.isRunningTests {
                EmptyView()
            } else {
                SettingsView()
                    .environment(AppModel.shared.preferences)
                    .environment(AppModel.shared.calendar)
                    .environment(AppModel.shared.reminders)
            }
        }
        .commands {
            DashboardCommands()
        }
    }
}

struct DashboardCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Reminder") { AppModel.shared.newTask() }
                .keyboardShortcut("n")
            Button("New Event") { AppModel.shared.newEvent() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandMenu("Dashboard") {
            Button("Refresh") { AppModel.shared.refreshAll() }
                .keyboardShortcut("r")
            Button("Go to Today") { AppModel.shared.calendar.goToToday() }
                .keyboardShortcut("t")
            Divider()
            Button("Day View") { AppModel.shared.calendar.viewMode = .day }
                .keyboardShortcut("1")
            Button("Month View") { AppModel.shared.calendar.viewMode = .month }
                .keyboardShortcut("2")
            Button("Previous Day or Month") { AppModel.shared.calendar.step(-1) }
                .keyboardShortcut("[")
            Button("Next Day or Month") { AppModel.shared.calendar.step(1) }
                .keyboardShortcut("]")
            Divider()
            Button("Toggle Desktop Mode") { AppModel.shared.windows.toggleMode() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Return to Normal Window") { AppModel.shared.setMode(.normal) }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Show Dashboard") { AppModel.shared.showDashboard() }
                .keyboardShortcut("0")
        }
    }
}
