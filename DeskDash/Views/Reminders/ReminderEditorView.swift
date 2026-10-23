import SwiftUI

/// Edits title, notes, due date/time and priority. Nothing is written until Save.
struct ReminderEditorView: View {
    let reminder: Reminder
    let dismiss: () -> Void

    @Environment(RemindersStore.self) private var store
    @State private var title: String
    @State private var notes: String
    @State private var hasDueDate: Bool
    @State private var hasTime: Bool
    @State private var dueDate: Date
    @State private var priority: ReminderPriority
    @FocusState private var titleFocused: Bool

    init(reminder: Reminder, dismiss: @escaping () -> Void) {
        self.reminder = reminder
        self.dismiss = dismiss
        _title = State(initialValue: reminder.title)
        _notes = State(initialValue: reminder.notes)
        _hasDueDate = State(initialValue: reminder.due != nil)
        _hasTime = State(initialValue: reminder.due?.hasTime ?? false)
        _priority = State(initialValue: reminder.priority)
        let fallback = Calendar.autoupdatingCurrent.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        _dueDate = State(initialValue: reminder.due.map { $0.hasTime ? $0.dueInstant() : (Calendar.autoupdatingCurrent.date(bySettingHour: 9, minute: 0, second: 0, of: $0.dueInstant()) ?? $0.dueInstant()) } ?? fallback)
    }

    private var editedDue: ReminderDue? {
        guard hasDueDate else { return nil }
        let date = TaskDueDate(date: dueDate)
        guard hasTime else { return ReminderDue(date: date) }
        let parts = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: dueDate)
        return ReminderDue(date: date, hour: parts.hour, minute: parts.minute)
    }

    private var edit: ReminderEdit {
        ReminderEdit(title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes, due: editedDue, priority: priority)
    }

    private var hasChanges: Bool { edit != reminder.edit }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.body.weight(.medium))
                .focused($titleFocused)
                .onSubmit(save)

            TextField("Notes", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Toggle("Date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.field)
                    }
                }
                if hasDueDate {
                    GridRow {
                        Toggle("Time", isOn: $hasTime)
                        if hasTime {
                            DatePicker("Time", selection: $dueDate, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .datePickerStyle(.field)
                        }
                    }
                }
                GridRow {
                    Text("Priority")
                    Picker("Priority", selection: $priority) {
                        ForEach(ReminderPriority.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            HStack(spacing: 6) {
                Circle().fill(reminder.listColor?.color ?? .accentColor).frame(width: 8, height: 8)
                Text(reminder.listTitle)
                if reminder.isRecurring {
                    Label("Repeats", systemImage: "repeat")
                        .padding(.leading, 6)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(edit.title.isEmpty || !hasChanges)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { titleFocused = true }
    }

    private func save() {
        guard !edit.title.isEmpty else { return }
        if hasChanges { store.save(reminder.id, edit: edit) }
        dismiss()
    }
}
