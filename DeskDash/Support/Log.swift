import Foundation
import os

/// Logging that records operation names, timings and status codes only.
///
/// Never pass reminder titles, notes, event details or locations to these loggers. Dynamic values that are not plainly safe use `.private`.
enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "net.hungngo.DeskDash"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let reminders = Logger(subsystem: subsystem, category: "reminders")
}
