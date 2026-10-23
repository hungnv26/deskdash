import SwiftUI

/// Return adds the reminder; Escape clears and leaves the field.
struct QuickAddView: View {
    let targetList: ReminderList
    let showsListName: Bool

    @Environment(RemindersStore.self) private var store
    @Environment(DashboardUIState.self) private var ui
    @State private var text = ""
    @State private var due: ReminderDue?
    @State private var choosingDate = false
    @State private var pickedDate = Date()
    @State private var pickedHasTime = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .foregroundStyle(targetList.color?.color ?? .accentColor)
                .font(.system(size: 15))
                .accessibilityHidden(true)
            TextField(showsListName ? "Add to \(targetList.title)" : "New Reminder", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(submit)
                .onExitCommand {
                    text = ""
                    due = nil
                    focused = false
                }
                .accessibilityLabel("New reminder in \(targetList.title)")
            dueMenu
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        // See-through field: an outline only, brighter while typing.
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(focused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.18), lineWidth: focused ? 1.5 : 1)
        )
        .onChange(of: ui.quickAddFocusRequest) { focused = true }
        // Stays visible while in use, so typing never disappears.
        .fadingChrome(forceVisible: focused || !text.isEmpty || due != nil)
    }

    private var dueMenu: some View {
        Menu {
            Button("Today") { due = ReminderDue(date: .today()) }
            Button("This Evening (6:00 pm)") { due = ReminderDue(date: .today(), hour: 18) }
            Button("Tomorrow") { due = ReminderDue(date: TaskDueDate.today().adding(days: 1)) }
            Button("Next Week") { due = ReminderDue(date: TaskDueDate.today().adding(days: 7)) }
            Button("Choose Date…") {
                pickedDate = due?.dueInstant() ?? Calendar.autoupdatingCurrent.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
                pickedHasTime = due?.hasTime ?? false
                choosingDate = true
            }
            if due != nil {
                Divider()
                Button("No Date") { due = nil }
            }
        } label: {
            if let due {
                Text(DueLabel.text(for: due, section: .upcoming, now: Date()) ?? "")
                    .font(.caption)
            } else {
                Image(systemName: "calendar")
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Due date (optional)")
        .accessibilityLabel(due.map { "Due \(DueLabel.text(for: $0, section: .upcoming, now: Date()) ?? "")" } ?? "Set due date")
        .popover(isPresented: $choosingDate) {
            VStack(alignment: .leading, spacing: 8) {
                DatePicker("Date", selection: $pickedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                HStack {
                    Toggle("Time", isOn: $pickedHasTime)
                    if pickedHasTime {
                        DatePicker("Time", selection: $pickedDate, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    Spacer()
                    Button("Set") {
                        let parts = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: pickedDate)
                        due = ReminderDue(date: TaskDueDate(date: pickedDate), hour: pickedHasTime ? parts.hour : nil, minute: parts.minute)
                        choosingDate = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
            .frame(width: 280)
        }
    }

    private func submit() {
        if store.create(title: text, due: due) {
            text = ""
            due = nil
        }
        focused = true
    }
}
