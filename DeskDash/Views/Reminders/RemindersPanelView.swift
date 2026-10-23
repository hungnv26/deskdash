import SwiftUI

struct RemindersPanelView: View {
    @Environment(RemindersStore.self) private var store
    @Environment(PreferencesStore.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            content
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reminders")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if store.authState == .granted, !store.lists.isEmpty {
                    listPicker
                }
            }
            Spacer()
            if store.authState == .granted {
                Menu {
                    Toggle("Show Completed", isOn: Binding(
                        get: { preferences.showCompletedReminders },
                        set: { preferences.showCompletedReminders = $0 }
                    ))
                    Divider()
                    Button("Open Reminders App") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app"))
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("View options")
                .accessibilityLabel("Reminder view options")
                .fadingChrome()
            }
        }
    }

    private var listPicker: some View {
        Menu {
            Button {
                store.selectList(nil)
            } label: {
                if store.selectedListID == nil {
                    Label("All Lists", systemImage: "checkmark")
                } else {
                    Text("All Lists")
                }
            }
            Divider()
            ForEach(store.lists) { list in
                Button {
                    store.selectList(list.id)
                } label: {
                    if list.id == store.selectedListID {
                        Label(list.title, systemImage: "checkmark")
                    } else {
                        Text(list.title)
                    }
                }
            }
        } label: {
            Text(store.selectedList?.title ?? "All Lists")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Reminders list: \(store.selectedList?.title ?? "All Lists")")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch store.authState {
        case .notDetermined:
            EmptyStateView(
                systemImage: "checklist",
                title: "Show your reminders",
                message: "DeskDash reads and updates Apple Reminders on this Mac. Anything you add, edit or complete syncs to your iPhone and iPad through iCloud."
            ) {
                Button("Allow Reminders Access…") { Task { await store.requestAccess() } }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            }
        case .denied, .restricted, .writeOnly:
            EmptyStateView(
                systemImage: "checklist.unchecked",
                title: "Reminders access is off",
                message: store.authState == .restricted
                    ? "Reminders access is restricted on this Mac, for example by a device-management profile."
                    : "Turn on Full Access for DeskDash in System Settings › Privacy & Security › Reminders, then come back."
            ) {
                if store.authState != .restricted {
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        case .granted:
            grantedContent
        }
    }

    @ViewBuilder
    private var grantedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let banner = store.banner {
                BannerView(
                    message: banner.message,
                    actionTitle: banner.retry == nil ? nil : "Retry",
                    action: banner.retry.map { action in { store.handleRetry(action) } },
                    dismiss: { store.dismissBanner() }
                )
                .padding(.horizontal, 12)
            }
            if let notice = store.notice {
                BannerView(message: notice, systemImage: "info.circle.fill", tint: .blue, dismiss: { store.notice = nil })
                    .padding(.horizontal, 12)
            }
            if let target = store.listForNewReminders, target.allowsModifications {
                QuickAddView(targetList: target, showsListName: store.selectedListID == nil)
                    .padding(.horizontal, 12)
            }
            reminderList
        }
    }

    @ViewBuilder
    private var reminderList: some View {
        if !store.hasLoaded {
            ProgressView("Loading reminders…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.lists.isEmpty {
            EmptyStateView(
                systemImage: "tray",
                title: "No reminder lists",
                message: "Create a list in the Reminders app. If you use iCloud, make sure Reminders is turned on in System Settings › Apple Account › iCloud."
            )
        } else {
            TimelineView(.everyMinute) { context in
                let groups = store.groups(now: context.date)
                if groups.isEmpty {
                    EmptyStateView(
                        systemImage: "checkmark.circle",
                        title: "All done",
                        message: "Nothing left in \(store.selectedList?.title ?? "your lists"). Add a reminder above."
                    )
                } else {
                    List {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.reminders) { reminder in
                                    ReminderRowView(
                                        reminder: reminder,
                                        section: group.section,
                                        showsList: store.selectedListID == nil,
                                        now: context.date
                                    )
                                }
                            } header: {
                                sectionHeader(group)
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, 30)
                }
            }
        }
    }

    private func sectionHeader(_ group: ReminderGroup) -> some View {
        HStack(spacing: 6) {
            Text(group.section.title)
            Text("\(group.reminders.count)")
                .foregroundStyle(.tertiary)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(group.section == .overdue ? Color.red : Color.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
