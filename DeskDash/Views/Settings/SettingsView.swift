import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            RemindersSettingsView()
                .tabItem { Label("Reminders", systemImage: "checklist") }
            CalendarSettingsView()
                .tabItem { Label("Calendars", systemImage: "calendar") }
        }
        .frame(width: 520)
        .scenePadding()
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @Environment(PreferencesStore.self) private var preferences
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Show dashboard as", selection: Binding(
                    get: { preferences.windowMode },
                    set: { AppModel.shared.setMode($0) }
                )) {
                    Text("Desktop (behind all windows)").tag(WindowMode.desktop)
                    Text("Normal window").tag(WindowMode.normal)
                }
                Picker("Desktop layer", selection: Binding(
                    get: { preferences.desktopLayer },
                    set: {
                        preferences.desktopLayer = $0
                        AppModel.shared.windows.applyDesktopLayer()
                    }
                )) {
                    ForEach(DesktopLayer.allCases) { layer in
                        Text(layer.title).tag(layer)
                    }
                }
                .disabled(preferences.windowMode != .desktop)
                Text("Desktop mode sits behind every app window on all Spaces. If it ever looks wrong, use Return to Normal Window in the menu-bar icon or press ⌥⌘N.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Desktop appearance") {
                LabeledContent("Transparency") {
                    HStack(spacing: 8) {
                        Text("Solid").font(.caption).foregroundStyle(.secondary)
                        Slider(value: Binding(
                            get: { preferences.desktopTransparency },
                            set: { preferences.desktopTransparency = $0 }
                        ), in: 0...1)
                        .frame(width: 200)
                        .accessibilityLabel("Panel transparency")
                        Text("Clear").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("Blur the wallpaper behind panels", isOn: Binding(
                    get: { preferences.desktopBlur && !reduceTransparency },
                    set: { preferences.desktopBlur = $0 }
                ))
                .disabled(reduceTransparency)
                if reduceTransparency {
                    Text("Blur is unavailable because Reduce transparency is on in System Settings › Accessibility › Display. Panels use a plain see-through tint instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Show buttons only when the pointer is over the dashboard", isOn: Binding(
                    get: { preferences.desktopControlsOnHover },
                    set: { preferences.desktopControlsOnHover = $0 }
                ))
                Text("Only the panel backgrounds fade; text always stays fully opaque. When panels are very clear, text gets a soft outline so it stays readable on any wallpaper. Changes show live.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(preferences.windowMode != .desktop)

            Section {
                Picker("Appearance", selection: Binding(
                    get: { preferences.appearance },
                    set: {
                        preferences.appearance = $0
                        AppModel.shared.applyAppearance()
                    }
                )) {
                    ForEach(AppearancePreference.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                Toggle("Open DeskDash at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginItemMessage {
                    Text(loginItemMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Refresh Now") { AppModel.shared.refreshAll() }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshLoginItemState() }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemMessage = "Couldn't change the login item: \(error.localizedDescription)"
        }
        refreshLoginItemState()
    }

    private func refreshLoginItemState() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            loginItemMessage = "Approve DeskDash in System Settings › General › Login Items."
        }
    }
}

// MARK: - Reminders

private struct RemindersSettingsView: View {
    @Environment(RemindersStore.self) private var store
    @Environment(PreferencesStore.self) private var preferences

    var body: some View {
        Form {
            switch store.authState {
            case .granted:
                Section("Show") {
                    Picker("List", selection: Binding(
                        get: { store.selectedListID ?? "" },
                        set: { store.selectList($0.isEmpty ? nil : $0) }
                    )) {
                        Text("All Lists").tag("")
                        ForEach(store.lists) { list in
                            Text(list.title).tag(list.id)
                        }
                    }
                    Toggle("Show completed reminders", isOn: Binding(
                        get: { preferences.showCompletedReminders },
                        set: { preferences.showCompletedReminders = $0 }
                    ))
                }
                Section("Lists on this Mac") {
                    if store.lists.isEmpty {
                        Text("No lists yet. Create one in the Reminders app.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.lists) { list in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(list.color?.color ?? .accentColor)
                                .frame(width: 10, height: 10)
                            Text(list.title)
                            Spacer()
                            Text(list.accountTitle + (list.allowsModifications ? "" : " · read-only"))
                                .foregroundStyle(.secondary)
                            if list.id == store.defaultListID {
                                Text("Default")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                }
                Section {
                    Text("Reminders sync to your iPhone and iPad through iCloud. Make sure Reminders is turned on in System Settings › Apple Account › iCloud on every device, with the same Apple Account. Lists under “On My Mac” stay on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .notDetermined:
                Button("Allow Reminders Access…") { Task { await store.requestAccess() } }
            default:
                Text("Reminders access is off. Turn on Full Access for DeskDash in System Settings › Privacy & Security › Reminders.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await store.reload() }
    }
}

// MARK: - Calendars

private struct CalendarSettingsView: View {
    @Environment(CalendarStore.self) private var calendar

    var body: some View {
        Form {
            switch calendar.authState {
            case .granted:
                if calendar.calendars.isEmpty {
                    Text("No calendars found. Add an account in Calendar › Settings › Accounts.")
                        .foregroundStyle(.secondary)
                }
                ForEach(accounts, id: \.self) { account in
                    Section(account) {
                        ForEach(calendar.calendars.filter { $0.accountTitle == account }) { source in
                            Toggle(isOn: Binding(
                                get: { calendar.isVisible(source) },
                                set: { calendar.setVisible($0, calendar: source) }
                            )) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(source.color?.color ?? .accentColor)
                                        .frame(width: 10, height: 10)
                                    Text(source.title)
                                }
                            }
                        }
                    }
                }
                Section {
                    Text("Missing iPhone events? Make sure that account is enabled in Calendar › Settings › Accounts on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .notDetermined:
                Button("Allow Calendar Access…") { Task { await calendar.requestAccess() } }
            default:
                Text("Calendar access is off. Turn on Full Access for DeskDash in System Settings › Privacy & Security › Calendars.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await calendar.reload() }
    }

    private var accounts: [String] {
        var seen = Set<String>()
        return calendar.calendars.map(\.accountTitle).filter { seen.insert($0).inserted }
    }
}
