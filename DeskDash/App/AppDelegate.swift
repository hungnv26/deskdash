import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        AppModel.shared.launch()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !Self.isRunningTests else { return true }
        AppModel.shared.showDashboard()
        return true
    }

    /// The dashboard lives on in the menu bar after its window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
