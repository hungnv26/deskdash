import AppKit
import Foundation
import Observation

enum WindowMode: String, CaseIterable, Identifiable, Sendable {
    /// Borderless dashboard pinned to the desktop layer, behind every app window.
    case desktop
    /// A conventional, resizable window. Always available as the fallback.
    case normal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: "Desktop"
        case .normal: "Window"
        }
    }
}

/// Where the desktop-mode window sits relative to Finder's desktop icons.
enum DesktopLayer: String, CaseIterable, Identifiable, Sendable {
    /// Just above the icon layer: fully clickable, covers desktop icons.
    case aboveIcons
    /// Just below the icon layer: icons stay visible on top. Finder takes clicks while
    /// another app is active; the dashboard rises above the icons while DeskDash is active.
    case belowIcons

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aboveIcons: "Interactive (covers desktop icons)"
        case .belowIcons: "Behind desktop icons (click the menu-bar icon to use)"
        }
    }
}

enum CalendarViewMode: String, CaseIterable, Identifiable, Sendable {
    case day
    case month

    var id: String { rawValue }
    var title: String { self == .day ? "Day" : "Month" }
}

enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// User preferences persisted in UserDefaults. Never holds credentials.
@MainActor
@Observable
final class PreferencesStore {
    @ObservationIgnored private let defaults: UserDefaults

    var windowMode: WindowMode {
        didSet { defaults.set(windowMode.rawValue, forKey: Key.windowMode) }
    }
    var desktopLayer: DesktopLayer {
        didSet { defaults.set(desktopLayer.rawValue, forKey: Key.desktopLayer) }
    }
    /// `nil` means "All lists".
    var selectedReminderListID: String? {
        didSet { defaults.set(selectedReminderListID, forKey: Key.selectedReminderListID) }
    }
    /// `nil` means "show every calendar", so new calendars appear automatically.
    var selectedCalendarIDs: Set<String>? {
        didSet { defaults.set(selectedCalendarIDs.map { Array($0).sorted() }, forKey: Key.selectedCalendarIDs) }
    }
    var calendarViewMode: CalendarViewMode {
        didSet { defaults.set(calendarViewMode.rawValue, forKey: Key.calendarViewMode) }
    }
    var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }
    /// Fraction of the dashboard width given to the reminders panel.
    var panelRatio: Double {
        didSet { defaults.set(panelRatio, forKey: Key.panelRatio) }
    }
    /// Desktop mode only. 0 = solid panels, 1 = fully clear (text only).
    var desktopTransparency: Double {
        didSet { defaults.set(desktopTransparency, forKey: Key.desktopTransparency) }
    }
    /// Desktop mode only. Frost the wallpaper behind panels.
    var desktopBlur: Bool {
        didSet { defaults.set(desktopBlur, forKey: Key.desktopBlur) }
    }
    /// Desktop mode only. Buttons fade out until the pointer is over the dashboard.
    var desktopControlsOnHover: Bool {
        didSet { defaults.set(desktopControlsOnHover, forKey: Key.desktopControlsOnHover) }
    }
    var showCompletedReminders: Bool {
        didSet { defaults.set(showCompletedReminders, forKey: Key.showCompletedReminders) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        windowMode = defaults.string(forKey: Key.windowMode).flatMap(WindowMode.init) ?? .normal
        desktopLayer = defaults.string(forKey: Key.desktopLayer).flatMap(DesktopLayer.init) ?? .aboveIcons
        selectedReminderListID = defaults.string(forKey: Key.selectedReminderListID)
        selectedCalendarIDs = (defaults.array(forKey: Key.selectedCalendarIDs) as? [String]).map(Set.init)
        calendarViewMode = defaults.string(forKey: Key.calendarViewMode).flatMap(CalendarViewMode.init) ?? .month
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppearancePreference.init) ?? .system
        let ratio = defaults.double(forKey: Key.panelRatio)
        panelRatio = (0.25...0.75).contains(ratio) ? ratio : 0.4
        showCompletedReminders = defaults.bool(forKey: Key.showCompletedReminders)
        let transparency = defaults.object(forKey: Key.desktopTransparency) as? Double
        desktopTransparency = min(max(transparency ?? 0.7, 0), 1)
        desktopBlur = defaults.object(forKey: Key.desktopBlur) as? Bool ?? true
        desktopControlsOnHover = defaults.object(forKey: Key.desktopControlsOnHover) as? Bool ?? true
    }

    private enum Key {
        static let windowMode = "windowMode"
        static let desktopLayer = "desktopLayer"
        static let selectedReminderListID = "selectedReminderListID"
        static let selectedCalendarIDs = "selectedCalendarIDs"
        static let calendarViewMode = "calendarViewMode"
        static let appearance = "appearance"
        static let panelRatio = "panelRatio"
        static let showCompletedReminders = "showCompletedReminders"
        static let desktopTransparency = "desktopTransparency"
        static let desktopBlur = "desktopBlur"
        static let desktopControlsOnHover = "desktopControlsOnHover"
    }
}
