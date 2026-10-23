import SwiftUI

struct ReminderRowView: View {
    let reminder: Reminder
    let section: ReminderSection
    let showsList: Bool
    let now: Date

    @Environment(RemindersStore.self) private var store
    @State private var isEditing = false
    @State private var isHovering = false

    private var editable: Bool { store.isEditable(reminder) }
    private var isPending: Bool { store.pending.contains(reminder.id) }
    private var listColor: Color { reminder.listColor?.color ?? .accentColor }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            checkbox
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if reminder.priority != .none {
                        Text(reminder.priority.marks)
                            .font(.body.weight(.bold))
                            .foregroundStyle(reminder.isCompleted ? Color.secondary : listColor)
                            .accessibilityLabel("\(reminder.priority.title) priority")
                    }
                    Text(reminder.title.isEmpty ? "New Reminder" : reminder.title)
                        .strikethrough(reminder.isCompleted)
                        .foregroundStyle(reminder.isCompleted ? .secondary : .primary)
                        .lineLimit(2)
                }
                if !reminder.notes.isEmpty {
                    Text(reminder.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if showsList {
                    HStack(spacing: 4) {
                        Circle().fill(listColor).frame(width: 6, height: 6)
                        Text(reminder.listTitle)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 8)
            if reminder.hasLocationAlert {
                Image(systemName: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(RemindersError.locationAlert.userMessage)
                    .accessibilityLabel("Has a location alert; change it in the Reminders app")
            }
            if reminder.isRecurring {
                Image(systemName: "repeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Repeats")
            }
            if let due = reminder.due, let label = DueLabel.text(for: due, section: section, now: now) {
                Text(label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(section == .overdue && !reminder.isCompleted ? Color.red : Color.secondary)
            }
            if isPending {
                ProgressView()
                    .controlSize(.mini)
                    .help("Saving to Reminders…")
                    .accessibilityLabel("Saving")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if editable {
                isEditing = true
            } else if reminder.hasLocationAlert {
                store.openInRemindersApp(reminder)
            }
        }
        .onHover { isHovering = $0 }
        .popover(isPresented: $isEditing, arrowEdge: .trailing) {
            ReminderEditorView(reminder: reminder) { isEditing = false }
        }
        .contextMenu {
            if editable {
                Button("Edit…") { isEditing = true }
                Button(reminder.isCompleted ? "Mark as Not Done" : "Mark as Done") {
                    store.setCompleted(reminder.id, !reminder.isCompleted)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Edit") { if editable { isEditing = true } }
    }

    private var checkbox: some View {
        Button {
            if reminder.hasLocationAlert {
                store.openInRemindersApp(reminder)
            } else {
                store.setCompleted(reminder.id, !reminder.isCompleted)
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(reminder.isCompleted ? listColor : (isHovering ? Color.primary : Color.secondary), lineWidth: 1.5)
                if reminder.isCompleted {
                    Circle().fill(listColor).padding(3)
                }
            }
            .frame(width: 17, height: 17)
            .contentShape(Circle())
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        }
        .buttonStyle(.plain)
        .disabled(!editable && !reminder.hasLocationAlert)
        .help(reminder.hasLocationAlert ? "Opens Reminders: reminders with location alerts can only be changed there" : "")
        .accessibilityLabel(reminder.isCompleted ? "Mark \(reminder.title) as not done" : "Mark \(reminder.title) as done")
    }
}

enum DueLabel {
    /// Short due label. Today's all-day reminders need no label in the Today section.
    static func text(for due: ReminderDue, section: ReminderSection, now: Date, calendar: Calendar = .autoupdatingCurrent) -> String? {
        let time = due.hasTime ? due.dueInstant(calendar: calendar).formatted(date: .omitted, time: .shortened) : nil
        let today = TaskDueDate(date: now, calendar: calendar)
        if due.date == today && (section == .today || section == .overdue) {
            return time ?? (section == .overdue ? "Today" : nil)
        }
        let day = dayText(for: due.date, today: today, calendar: calendar)
        return [day, time].compactMap { $0 }.joined(separator: ", ")
    }

    /// "Today", "Tomorrow", "Yesterday", a weekday within the next week, otherwise a short date.
    static func dayText(for date: TaskDueDate, today: TaskDueDate, calendar: Calendar = .autoupdatingCurrent) -> String {
        if date == today { return "Today" }
        if date == today.adding(days: 1) { return "Tomorrow" }
        if date == today.adding(days: -1) { return "Yesterday" }
        let start = date.startOfDay(in: calendar)
        if date > today && date <= today.adding(days: 6) {
            return start.formatted(.dateTime.weekday(.abbreviated))
        }
        if date.year == today.year {
            return start.formatted(.dateTime.day().month(.abbreviated))
        }
        return start.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
