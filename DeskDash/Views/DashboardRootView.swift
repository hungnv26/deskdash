import SwiftUI

/// The whole dashboard: a header strip above the reminders and calendar panels.
struct DashboardRootView: View {
    let mode: WindowMode

    @Environment(PreferencesStore.self) private var preferences
    @Environment(DashboardUIState.self) private var ui
    @Environment(\.openSettings) private var openSettings
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var dragStartRatio: Double?

    /// Desktop mode can hide controls until the pointer is over the dashboard or it has focus.
    private var chromeVisible: Bool {
        mode == .normal
            || !preferences.desktopControlsOnHover
            || ui.pointerInside
            || controlActiveState == .key
    }

    private let gap: CGFloat = 14
    private let minimumPanelWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: gap) {
            DashboardHeaderView(mode: mode)
            GeometryReader { proxy in
                let available = max(proxy.size.width - gap, minimumPanelWidth * 2)
                let taskWidth = clampedTaskWidth(available: available)
                HStack(spacing: 0) {
                    RemindersPanelView()
                        .frame(width: taskWidth)
                        .panelCard(mode)
                    divider(available: available)
                    CalendarPanelView()
                        .frame(maxWidth: .infinity)
                        .panelCard(mode)
                }
            }
        }
        .padding(mode == .desktop ? 0 : gap)
        .environment(\.chromeVisible, chromeVisible)
        .background {
            if mode == .normal {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            } else {
                PointerTracker { inside in ui.pointerInside = inside }
            }
        }
        .onAppear {
            AppModel.shared.openSettingsAction = { openSettings() }
        }
    }

    private func clampedTaskWidth(available: CGFloat) -> CGFloat {
        let proposed = available * preferences.panelRatio
        return min(max(proposed, minimumPanelWidth), available - minimumPanelWidth)
    }

    /// The gap between panels. In window mode it can be dragged to resize them.
    @ViewBuilder
    private func divider(available: CGFloat) -> some View {
        let handle = Rectangle()
            .fill(Color.clear)
            .frame(width: gap)
            .contentShape(Rectangle())
        if mode == .normal {
            handle
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let start = dragStartRatio ?? preferences.panelRatio
                            if dragStartRatio == nil { dragStartRatio = start }
                            let ratio = start + value.translation.width / available
                            preferences.panelRatio = min(max(ratio, 0.25), 0.7)
                        }
                        .onEnded { _ in dragStartRatio = nil }
                )
                .accessibilityLabel("Panel divider")
        } else {
            handle
        }
    }
}

/// Today's date and dashboard-level controls.
struct DashboardHeaderView: View {
    let mode: WindowMode

    @Environment(\.dashboardActions) private var actions

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 0) {
                    Text(context.date, format: .dateTime.weekday(.wide))
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(context.date, format: .dateTime.day().month(.wide).year())
                        .font(.title2.weight(.semibold))
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 12)
            IconButton(systemImage: "arrow.clockwise", label: "Refresh (⌘R)", action: actions.refresh)
                .fadingChrome()
            // The mode switch stays visible in both modes so it's always findable.
            IconButton(
                systemImage: mode == .desktop ? "macwindow" : "menubar.dock.rectangle",
                label: mode == .desktop
                    ? "Bring to front as a normal window (⇧⌘D)"
                    : "Send to desktop as a transparent layer (⇧⌘D)",
                action: actions.toggleMode
            )
            HStack(spacing: 10) {
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
            }
            .fadingChrome()
        }
        .padding(.horizontal, mode == .desktop ? 8 : 6)
        // In desktop mode the header sits straight on the wallpaper, so it always gets the outline.
        .readableOverWallpaper(mode == .desktop)
    }
}
