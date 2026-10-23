import SwiftUI

struct CalendarPanelView: View {
    @Environment(CalendarStore.self) private var calendar
    @State private var newEventDraft: EventDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .onChange(of: calendar.newEventRequest) { openNewEvent() }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            content
        }
    }

    // MARK: - Header

    private var periodTitle: String {
        switch calendar.viewMode {
        case .day:
            calendar.selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide))
        case .month:
            calendar.displayedMonth.formatted(.dateTime.month(.wide).year())
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(periodTitle)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            HollowSegmentedPicker(
                options: CalendarViewMode.allCases,
                selection: Binding(get: { calendar.viewMode }, set: { calendar.viewMode = $0 }),
                title: \.title
            )
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Calendar view")
            .fadingChrome()

            if calendar.authState == .granted, calendar.calendarForNewEvents != nil {
                IconButton(systemImage: "plus", label: "New event (⇧⌘E)") { openNewEvent() }
                    .popover(isPresented: Binding(
                        get: { newEventDraft != nil },
                        set: { if !$0 { newEventDraft = nil } }
                    ), arrowEdge: .bottom) {
                        if let draft = newEventDraft {
                            EventEditorView(mode: .create, draft: draft) { newEventDraft = nil }
                        }
                    }
                    .fadingChrome(forceVisible: newEventDraft != nil)
            }

            HStack(spacing: 2) {
                IconButton(systemImage: "chevron.left", label: calendar.viewMode == .day ? "Previous day" : "Previous month") {
                    calendar.step(-1)
                }
                Button("Today") { calendar.goToToday() }
                    .buttonStyle(HollowButtonStyle())
                    .focusEffectDisabled()
                    .help("Go to today (⌘T)")
                IconButton(systemImage: "chevron.right", label: calendar.viewMode == .day ? "Next day" : "Next month") {
                    calendar.step(1)
                }
            }
            .fadingChrome()
        }
    }

    private func openNewEvent() {
        newEventDraft = calendar.newEventDraft()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch calendar.authState {
        case .notDetermined:
            EmptyStateView(
                systemImage: "calendar",
                title: "Show your calendar",
                message: "DeskDash shows the calendars already set up in macOS Calendar, including iCloud and accounts synced from your iPhone, and lets you add and edit events. Changes sync to your other devices through those accounts."
            ) {
                Button("Allow Calendar Access…") { Task { await calendar.requestAccess() } }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            }
        case .denied, .restricted, .writeOnly:
            EmptyStateView(
                systemImage: "calendar.badge.exclamationmark",
                title: "Calendar access is off",
                message: calendar.authState == .restricted
                    ? "Calendar access is restricted on this Mac, for example by a device-management profile."
                    : "Turn on Full Access for DeskDash in System Settings › Privacy & Security › Calendars, then come back."
            ) {
                if calendar.authState != .restricted {
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        case .granted:
            grantedContent
        }
    }

    @ViewBuilder
    private var grantedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice = calendar.notice {
                BannerView(message: notice, systemImage: "info.circle.fill", tint: .blue, dismiss: { calendar.notice = nil })
                    .padding(.horizontal, 12)
            }
            if calendar.hasLoaded && calendar.calendars.isEmpty {
                EmptyStateView(
                    systemImage: "calendar.badge.plus",
                    title: "No calendars on this Mac",
                    message: "Add or enable an account in Calendar › Settings › Accounts. Events from your iPhone appear once that account syncs to this Mac."
                )
            } else if calendar.visibleCalendarIDs?.isEmpty == true {
                EmptyStateView(
                    systemImage: "eye.slash",
                    title: "All calendars are hidden",
                    message: "Choose which calendars to show in Settings › Calendars."
                ) {
                    SettingsLink { Text("Open Settings…") }
                }
            } else {
                switch calendar.viewMode {
                case .day:
                    DayAgendaView(date: calendar.selectedDate, agenda: calendar.selectedAgenda)
                case .month:
                    monthContent
                }
            }
        }
    }

    private var monthContent: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                MonthGridView()
                    .padding(.horizontal, 12)
                    .frame(height: max(proxy.size.height * 0.58, 220))
                Divider()
                    .padding(.horizontal, 12)
                HStack {
                    Text(calendar.selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.headline)
                    Spacer()
                    Button("Open Day") { calendar.viewMode = .day }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .fadingChrome()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                DayAgendaView(date: calendar.selectedDate, agenda: calendar.selectedAgenda, compact: true)
            }
        }
    }
}
