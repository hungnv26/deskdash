import AppKit

/// Menu-bar item: always reachable, even if the desktop window ends up somewhere odd.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private unowned let model: AppModel
    private let modeItem = NSMenuItem(title: "", action: #selector(toggleMode), keyEquivalent: "")

    init(model: AppModel) {
        self.model = model
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "DeskDash")
            button.image?.isTemplate = true
            button.toolTip = "DeskDash"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(makeItem("Use Dashboard", #selector(showDashboard)))
        modeItem.target = self
        menu.addItem(modeItem)
        menu.addItem(makeItem("Return to Normal Window", #selector(returnToNormal)))
        menu.addItem(.separator())
        menu.addItem(makeItem("New Reminder", #selector(newTask)))
        menu.addItem(makeItem("New Event", #selector(newEvent)))
        menu.addItem(makeItem("Refresh", #selector(refresh)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(openSettings)))
        menu.addItem(makeItem("Quit DeskDash", #selector(quit)))
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        modeItem.title = model.preferences.windowMode == .desktop ? "Switch to Window Mode" : "Switch to Desktop Mode"
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func showDashboard() { model.showDashboard() }
    @objc private func toggleMode() { model.windows.toggleMode() }
    @objc private func returnToNormal() { model.setMode(.normal) }
    @objc private func newTask() { model.newTask() }
    @objc private func newEvent() { model.newEvent() }
    @objc private func refresh() { model.refreshAll() }
    @objc private func openSettings() { model.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
