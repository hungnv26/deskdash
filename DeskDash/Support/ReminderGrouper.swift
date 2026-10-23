import Foundation

enum ReminderSection: String, CaseIterable, Identifiable, Sendable {
    case overdue
    case today
    case upcoming
    case later
    case noDueDate
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .later: "Later"
        case .noDueDate: "No due date"
        case .completed: "Completed"
        }
    }
}

struct ReminderGroup: Identifiable, Equatable, Sendable {
    var section: ReminderSection
    var reminders: [Reminder]
    var id: ReminderSection { section }
}

/// Splits reminders into the dashboard's sections.
///
/// - Overdue: due before today, or due today at a time that has passed.
/// - Upcoming: the next 7 days after today. Later: anything further out, so nothing disappears.
/// - Reminders in `keepInPlace` (just completed here) stay where they were for a moment
///   instead of jumping to Completed.
enum ReminderGrouper {
    static let upcomingDays = 7
    static let completedLimit = 25

    static func group(
        _ reminders: [Reminder],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        keepInPlace: Set<String> = [],
        showCompleted: Bool = false
    ) -> [ReminderGroup] {
        let today = TaskDueDate(date: now, calendar: calendar)
        let horizon = today.adding(days: upcomingDays)
        var buckets: [ReminderSection: [Reminder]] = [:]

        for reminder in reminders {
            if reminder.isCompleted && !keepInPlace.contains(reminder.id) {
                if showCompleted { buckets[.completed, default: []].append(reminder) }
                continue
            }
            buckets[section(for: reminder.due, today: today, horizon: horizon, now: now, calendar: calendar), default: []].append(reminder)
        }

        return ReminderSection.allCases.compactMap { section in
            guard var items = buckets[section], !items.isEmpty else { return nil }
            if section == .completed {
                items.sort { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
                items = Array(items.prefix(completedLimit))
            } else {
                items.sort { order($0, $1, calendar: calendar) }
            }
            return ReminderGroup(section: section, reminders: items)
        }
    }

    static func isOverdue(_ due: ReminderDue, now: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        let today = TaskDueDate(date: now, calendar: calendar)
        if due.date < today { return true }
        return due.date == today && due.hasTime && due.dueInstant(calendar: calendar) <= now
    }

    private static func section(for due: ReminderDue?, today: TaskDueDate, horizon: TaskDueDate, now: Date, calendar: Calendar) -> ReminderSection {
        guard let due else { return .noDueDate }
        if isOverdue(due, now: now, calendar: calendar) { return .overdue }
        if due.date == today { return .today }
        if due.date <= horizon { return .upcoming }
        return .later
    }

    /// Due date; all-day before timed on the same date, then by time; then priority;
    /// then creation date; then title.
    static func order(_ lhs: Reminder, _ rhs: Reminder, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        switch (lhs.due, rhs.due) {
        case let (l?, r?):
            if l.date != r.date { return l.date < r.date }
            if l.hasTime != r.hasTime { return !l.hasTime }
            if l.hasTime, l.dueInstant(calendar: calendar) != r.dueInstant(calendar: calendar) {
                return l.dueInstant(calendar: calendar) < r.dueInstant(calendar: calendar)
            }
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): break
        }
        if lhs.priority.sortRank != rhs.priority.sortRank { return lhs.priority.sortRank < rhs.priority.sortRank }
        let lc = lhs.creationDate ?? .distantFuture
        let rc = rhs.creationDate ?? .distantFuture
        if lc != rc { return lc < rc }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
