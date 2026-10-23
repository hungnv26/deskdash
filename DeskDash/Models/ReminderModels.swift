import Foundation

/// A reminder's due date, with an optional time of day.
///
/// Reminders without a time are "all-day": they belong to a calendar date, not an
/// instant, so the date part is kept as a `TaskDueDate` and never converted through
/// a time zone.
struct ReminderDue: Hashable, Sendable {
    var date: TaskDueDate
    var hour: Int?
    var minute: Int?

    var hasTime: Bool { hour != nil }

    init(date: TaskDueDate, hour: Int? = nil, minute: Int? = nil) {
        self.date = date
        self.hour = hour
        self.minute = hour == nil ? nil : (minute ?? 0)
    }

    /// From EventKit's `dueDateComponents`. Returns nil if there's no usable date.
    init?(components: DateComponents?, calendar: Calendar = .autoupdatingCurrent) {
        guard let components else { return nil }
        if let year = components.year, let month = components.month, let day = components.day {
            self.init(date: TaskDueDate(year: year, month: month, day: day), hour: components.hour, minute: components.minute)
        } else if let date = components.date {
            self.init(date: TaskDueDate(date: date, calendar: calendar))
        } else {
            return nil
        }
    }

    /// For writing back to EventKit. EventKit requires a Gregorian calendar here.
    /// Timed reminders carry the local time zone; all-day ones float.
    func components(timeZone: TimeZone = .autoupdatingCurrent) -> DateComponents {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = date.year
        components.month = date.month
        components.day = date.day
        if let hour {
            components.hour = hour
            components.minute = minute ?? 0
            components.timeZone = timeZone
        }
        return components
    }

    /// The moment the reminder is due: its time, or local midnight for all-day reminders.
    func dueInstant(calendar: Calendar = .autoupdatingCurrent) -> Date {
        let start = date.startOfDay(in: calendar)
        guard let hour else { return start }
        return calendar.date(bySettingHour: hour, minute: minute ?? 0, second: 0, of: start) ?? start
    }
}

/// EventKit priority: 0 none, 1–4 high, 5 medium, 6–9 low.
enum ReminderPriority: Int, CaseIterable, Identifiable, Sendable {
    case none = 0
    case high = 1
    case medium = 5
    case low = 9

    var id: Int { rawValue }

    init(eventKitValue: Int) {
        switch eventKitValue {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    var title: String {
        switch self {
        case .none: "None"
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    /// Reminders-style marks: "!!!", "!!", "!".
    var marks: String {
        switch self {
        case .none: ""
        case .high: "!!!"
        case .medium: "!!"
        case .low: "!"
        }
    }

    /// Lower sorts first.
    var sortRank: Int {
        switch self {
        case .high: 0
        case .medium: 1
        case .low: 2
        case .none: 3
        }
    }
}

/// A Reminders list (an `EKCalendar` of type reminder).
struct ReminderList: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    /// The account the list belongs to, such as "iCloud" or "On My Mac".
    var accountTitle: String
    var color: RGBAColor?
    var allowsModifications: Bool = true
}

/// The fields DeskDash can edit.
struct ReminderEdit: Hashable, Sendable {
    var title: String
    var notes: String
    var due: ReminderDue?
    var priority: ReminderPriority
}

/// Immutable, app-facing copy of an `EKReminder`.
struct Reminder: Identifiable, Hashable, Sendable {
    /// EventKit's `calendarItemIdentifier`.
    var id: String
    var listID: String
    var listTitle: String
    var listColor: RGBAColor?
    var title: String
    var notes: String
    var due: ReminderDue?
    var priority: ReminderPriority
    var isCompleted: Bool
    var completionDate: Date?
    var creationDate: Date?
    var isRecurring: Bool
    /// Reminders with a location-based alert ("when I arrive/leave") can't be saved through
    /// EventKit on macOS 27: EventKit crashes inside its own save code. DeskDash shows them
    /// read-only and sends you to the Reminders app instead.
    var hasLocationAlert: Bool

    var edit: ReminderEdit {
        get { ReminderEdit(title: title, notes: notes, due: due, priority: priority) }
        set {
            title = newValue.title
            notes = newValue.notes
            due = newValue.due
            priority = newValue.priority
        }
    }

    init(
        id: String,
        listID: String,
        listTitle: String = "",
        listColor: RGBAColor? = nil,
        title: String,
        notes: String = "",
        due: ReminderDue? = nil,
        priority: ReminderPriority = .none,
        isCompleted: Bool = false,
        completionDate: Date? = nil,
        creationDate: Date? = nil,
        isRecurring: Bool = false,
        hasLocationAlert: Bool = false
    ) {
        self.id = id
        self.listID = listID
        self.listTitle = listTitle
        self.listColor = listColor
        self.title = title
        self.notes = notes
        self.due = due
        self.priority = priority
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.creationDate = creationDate
        self.isRecurring = isRecurring
        self.hasLocationAlert = hasLocationAlert
    }
}

enum RemindersError: Error, Equatable, Sendable {
    case accessDenied
    case notFound
    case readOnlyList
    case noDefaultList
    case locationAlert
    case saveFailed(String)

    var userMessage: String {
        switch self {
        case .accessDenied: "DeskDash doesn't have access to Reminders."
        case .notFound: "That reminder no longer exists. It may have been deleted on another device."
        case .readOnlyList: "That list is read-only."
        case .noDefaultList: "There's no default Reminders list. Choose a list first."
        case .locationAlert: "This reminder has a location alert. macOS doesn't let other apps change those, so complete or edit it in the Reminders app."
        case .saveFailed(let detail): "Couldn't save to Reminders: \(detail)"
        }
    }
}
