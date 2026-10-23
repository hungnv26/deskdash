import Foundation
import AppKit
import SwiftUI

/// An sRGB colour that can cross concurrency domains and be persisted.
struct RGBAColor: Hashable, Codable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init?(_ nsColor: NSColor?) {
        guard let rgb = nsColor?.usingColorSpace(.sRGB) else { return nil }
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent)
    }
}

enum CalendarAuthState: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
    /// The app has write-only access, which cannot read events.
    case writeOnly
}

/// A calendar configured in macOS Calendar.
struct CalendarSource: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    /// The account the calendar belongs to, such as "iCloud" or a Google address.
    var accountTitle: String
    var color: RGBAColor?
    /// False for subscribed, holiday and birthday calendars.
    var allowsModifications: Bool = true
}

/// Immutable, app-facing copy of an EventKit event occurrence.
struct CalendarEvent: Identifiable, Hashable, Sendable {
    /// Unique per occurrence (recurring events share an EventKit identifier).
    var id: String
    var calendarID: String
    var calendarTitle: String
    var calendarColor: RGBAColor?
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var location: String?
    var notes: String?
    /// EventKit's `eventIdentifier`, shared by every occurrence of a repeating event.
    var eventIdentifier: String? = nil
    /// The original start of this occurrence, used to find it again for editing.
    var occurrenceDate: Date? = nil
    var isRecurring: Bool = false
    /// How the event repeats. `.custom` means a pattern DeskDash shows but doesn't edit.
    var repeatRule: EventRepeat = .never
    /// Why DeskDash can't change this event, or nil if it can.
    var readOnlyReason: String? = nil

    var isEditable: Bool { readOnlyReason == nil }
}

/// The repeat options DeskDash offers, matching the common choices in Calendar.
enum RepeatFrequency: String, CaseIterable, Identifiable, Sendable {
    case never
    case daily
    case weekly
    case biweekly
    case monthly
    case yearly
    /// Any other pattern (weekdays only, "2nd Tuesday", a set number of times…). Kept as is.
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: "Never"
        case .daily: "Every Day"
        case .weekly: "Every Week"
        case .biweekly: "Every 2 Weeks"
        case .monthly: "Every Month"
        case .yearly: "Every Year"
        case .custom: "Custom"
        }
    }

    /// Lower-case phrase for summaries: "every week".
    var phrase: String {
        switch self {
        case .never: "never"
        case .daily: "every day"
        case .weekly: "every week"
        case .biweekly: "every 2 weeks"
        case .monthly: "every month"
        case .yearly: "every year"
        case .custom: "on a custom schedule"
        }
    }

    /// The choices offered in the editor (Custom only appears for events that already have one).
    static let editable: [RepeatFrequency] = [.never, .daily, .weekly, .biweekly, .monthly, .yearly]
}

struct EventRepeat: Hashable, Sendable {
    var frequency: RepeatFrequency
    /// The last day a repeat can occur on; nil repeats forever.
    var endDate: Date?

    static let never = EventRepeat(frequency: .never, endDate: nil)

    var repeats: Bool { frequency != .never }

    /// "Repeats every week until 1 Dec 2026", or nil for non-repeating events.
    var summary: String? {
        guard repeats else { return nil }
        var text = "Repeats \(frequency.phrase)"
        if let endDate, frequency != .custom {
            text += " until " + endDate.formatted(.dateTime.day().month(.abbreviated).year())
        }
        return text
    }
}

/// The editable fields of an event. For all-day events, `end` is any moment on the last day.
struct EventDraft: Hashable, Sendable {
    var title: String
    var isAllDay: Bool
    var start: Date
    var end: Date
    var location: String
    var notes: String
    var calendarID: String
    var repeatRule: EventRepeat = .never

    /// A new one-hour event on `day`: at the next whole hour if `day` is today, otherwise 9:00.
    static func new(on day: Date, calendarID: String, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> EventDraft {
        let start: Date
        if calendar.isDate(day, inSameDayAs: now) {
            let nextHour = calendar.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? now
            start = calendar.isDate(nextHour, inSameDayAs: day) ? nextHour : calendar.date(bySettingHour: 23, minute: 0, second: 0, of: day)!
        } else {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }
        return EventDraft(title: "", isAllDay: false, start: start, end: start.addingTimeInterval(3600),
                          location: "", notes: "", calendarID: calendarID)
    }

    init(title: String, isAllDay: Bool, start: Date, end: Date, location: String, notes: String, calendarID: String) {
        self.title = title
        self.isAllDay = isAllDay
        self.start = start
        self.end = end
        self.location = location
        self.notes = notes
        self.calendarID = calendarID
    }

    init(event: CalendarEvent) {
        self.init(
            title: event.title,
            isAllDay: event.isAllDay,
            start: event.startDate,
            // All-day events end at the following midnight; show the last day instead.
            end: event.isAllDay ? max(event.startDate, event.endDate.addingTimeInterval(-1)) : event.endDate,
            location: event.location ?? "",
            notes: event.notes ?? "",
            calendarID: event.calendarID
        )
        repeatRule = event.repeatRule
    }

    /// The interval EventKit should store: whole days for all-day events.
    func normalizedDates(calendar: Calendar = .autoupdatingCurrent) -> (start: Date, end: Date) {
        guard isAllDay else { return (start, end) }
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: max(start, end))
        let afterLast = calendar.date(byAdding: .day, value: 1, to: last) ?? last.addingTimeInterval(86_400)
        return (first, afterLast)
    }

    /// Why the draft can't be saved yet, or nil.
    func validationMessage(calendar: Calendar = .autoupdatingCurrent) -> String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add a title." }
        if isAllDay {
            if calendar.startOfDay(for: end) < calendar.startOfDay(for: start) { return "The end date is before the start date." }
        } else if end <= start {
            return "The end time must be after the start time."
        }
        if repeatRule.repeats, repeatRule.frequency != .custom, let repeatEnd = repeatRule.endDate,
           calendar.startOfDay(for: repeatEnd) < calendar.startOfDay(for: start) {
            return "The repeat must end on or after the event's first day."
        }
        return nil
    }
}

/// Which occurrences of a repeating event an edit applies to.
enum EventSpan: String, CaseIterable, Identifiable, Sendable {
    case thisEvent
    case futureEvents

    var id: String { rawValue }
    var title: String { self == .thisEvent ? "This event only" : "This and future events" }
}

enum CalendarWriteError: Error, Equatable, Sendable {
    case notFound
    case readOnly(String)
    case invalid(String)
    case saveFailed(String)

    var userMessage: String {
        switch self {
        case .notFound: "That event no longer exists. It may have been deleted on another device."
        case .readOnly(let reason): reason
        case .invalid(let reason): reason
        case .saveFailed(let detail): "Couldn't save to Calendar: \(detail)"
        }
    }

    static func from(_ error: Error) -> CalendarWriteError {
        (error as? CalendarWriteError) ?? .saveFailed(error.localizedDescription)
    }
}
