import AppKit
import SwiftUI

/// Borderless window that can still take keyboard focus, so text fields work in desktop mode.
final class DesktopDashboardWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the dashboard window and applies the desktop/normal mode.
///
/// All window-level and collection-behaviour changes live here; SwiftUI views never
/// touch window levels. Switching modes builds a fresh window around the same shared
/// state objects, so the selected date, list and preferences carry over.
@MainActor
final class DashboardWindowController: NSObject, NSWindowDelegate {
    private let preferences: PreferencesStore
    private let makeRootView: (WindowMode) -> AnyView
    private(set) var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    private static let normalAutosaveName = "DeskDashNormalWindow"
    private static let minimumSize = NSSize(width: 760, height: 480)
    private static let desktopInset: CGFloat = 24

    init(preferences: PreferencesStore, makeRootView: @escaping (WindowMode) -> AnyView) {
        self.preferences = preferences
        self.makeRootView = makeRootView
        super.init()
        observeEnvironmentChanges()
    }

    var mode: WindowMode { preferences.windowMode }

    /// Shows the dashboard in the current mode, creating the window if needed.
    func show() {
        if window == nil { buildWindow() }
        guard let window else { return }
        switch mode {
        case .normal:
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        case .desktop:
            positionDesktopWindow()
            // Ordering front only reorders within the desktop level; it never rises above app windows.
            window.orderFrontRegardless()
        }
    }

    /// Gives the dashboard keyboard focus without moving it above other apps in desktop mode.
    func focus() {
        if window == nil { buildWindow() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func setMode(_ newMode: WindowMode) {
        guard newMode != preferences.windowMode || window == nil else {
            show()
            return
        }
        Log.window.info("Switching window mode to \(newMode.rawValue, privacy: .public)")
        preferences.windowMode = newMode
        tearDownWindow()
        buildWindow()
        show()
    }

    func toggleMode() {
        setMode(mode == .desktop ? .normal : .desktop)
    }

    /// Re-applies the desktop layer after the user changes it in Settings.
    func applyDesktopLayer() {
        guard mode == .desktop, let window else { return }
        window.level = currentDesktopLevel()
        window.ignoresMouseEvents = false
        window.orderFrontRegardless()
    }

    /// "Behind desktop icons" is display-only because Finder's icon layer takes the clicks.
    /// While DeskDash is the active app, the dashboard rises above the icons so it can be
    /// used; when another app becomes active it drops back behind them.
    private func currentDesktopLevel() -> NSWindow.Level {
        if preferences.desktopLayer == .belowIcons && NSApp.isActive {
            return Self.level(for: .aboveIcons)
        }
        return Self.level(for: preferences.desktopLayer)
    }

    // MARK: - Window construction

    private func buildWindow() {
        let window: NSWindow
        switch mode {
        case .normal:
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "DeskDash"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.minSize = Self.minimumSize
            window.collectionBehavior = [.fullScreenPrimary]
            window.tabbingMode = .disallowed
            window.isReleasedWhenClosed = false
            if !window.setFrameUsingName(Self.normalAutosaveName) {
                window.center()
            }
            window.setFrameAutosaveName(Self.normalAutosaveName)

        case .desktop:
            window = DesktopDashboardWindow(
                contentRect: desktopFrame(),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.level = currentDesktopLevel()
            // Catch clicks across the whole window, even where a fully clear panel
            // would otherwise let them fall through to Finder.
            window.ignoresMouseEvents = false
            // Visible on every Space, ignored by Mission Control's window shuffle and ⌘` cycling.
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isMovable = false
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
        }

        window.delegate = self
        window.isRestorable = false
        let hosting = NSHostingView(rootView: makeRootView(mode))
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        self.window = window
    }

    private func tearDownWindow() {
        guard let window else { return }
        window.delegate = nil
        window.orderOut(nil)
        window.contentView = nil
        self.window = nil
    }

    // MARK: - Desktop placement

    /// Desktop windows sit one step above (interactive) or below (display-only) Finder's icon layer.
    static func level(for layer: DesktopLayer) -> NSWindow.Level {
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        switch layer {
        case .aboveIcons: return NSWindow.Level(rawValue: iconLevel + 1)
        case .belowIcons: return NSWindow.Level(rawValue: iconLevel - 1)
        }
    }

    /// The primary display's usable area (excludes menu bar and Dock), inset slightly.
    private func desktopFrame() -> NSRect {
        let screen = NSScreen.screens.first ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return NSRect(x: 0, y: 0, width: 1280, height: 800) }
        return visible.insetBy(dx: Self.desktopInset, dy: Self.desktopInset)
    }

    private func positionDesktopWindow() {
        guard mode == .desktop, let window else { return }
        let frame = desktopFrame()
        if window.frame != frame {
            window.setFrame(frame, display: true)
        }
    }

    /// Makes sure a normal window is never stranded on a display that went away.
    private func rescueNormalWindowIfOffscreen() {
        guard mode == .normal, let window else { return }
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
        if !onScreen {
            window.center()
        }
    }

    private func observeEnvironmentChanges() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleDisplayChange() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleDisplayChange() }
        })
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyDesktopLayer() }
            })
        }
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.mode == .desktop else { return }
                self.window?.orderFrontRegardless()
            }
        })
    }

    private func handleDisplayChange() {
        Log.window.info("Display configuration changed; repositioning dashboard")
        positionDesktopWindow()
        rescueNormalWindowIfOffscreen()
    }
}
