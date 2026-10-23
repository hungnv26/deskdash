import SwiftUI

/// All-day events first, then timed events in order. Read-only.
struct DayAgendaView: View {
    let date: Date
    let agenda: (allDay: [CalendarEvent], timed: [CalendarEvent])
    var compact = false

    @Environment(CalendarStore.self) private var calendar

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if agenda.allDay.isEmpty && agenda.timed.isEmpty {
                    VStack(spacing: 8) {
                        Text(calendar.isLoading ? "Loading…" : "No events")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if !calendar.isLoading, calendar.calendarForNewEvents != nil {
                            Button("Add Event") { calendar.newEventRequest += 1 }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .fadingChrome()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, compact ? 16 : 40)
                }
                if !agenda.allDay.isEmpty {
                    FlowChips(events: agenda.allDay)
                        .padding(.bottom, 4)
                }
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(agenda.timed) { event in
                            EventRowView(event: event, day: date, now: context.date)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

/// All-day events as coloured chips.
private struct FlowChips: View {
    let events: [CalendarEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(events) { event in
                AllDayChip(event: event)
            }
        }
    }
}

private struct AllDayChip: View {
    let event: CalendarEvent
    @State private var showingDetails = false

    var body: some View {
        let color = event.calendarColor?.color ?? .accentColor
        Button { showingDetails = true } label: {
            HStack(spacing: 6) {
                Text("All day")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(event.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.20), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 7)
                    .fill(color)
                    .frame(width: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingDetails, arrowEdge: .leading) { EventDetailView(event: event) { showingDetails = false } }
        .accessibilityLabel("All-day event: \(event.title), \(event.calendarTitle)")
    }
}

struct EventRowView: View {
    let event: CalendarEvent
    let day: Date
    let now: Date

    @Environment(CalendarStore.self) private var calendar
    @State private var showingDetails = false

    var body: some View {
        let math = calendar.math
        let dayInterval = math.dayInterval(containing: day)
        let color = event.calendarColor?.color ?? .accentColor
        let isPast = event.endDate <= now
        let isNow = event.startDate <= now && now < event.endDate

        Button { showingDetails = true } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(event.startDate < dayInterval.start ? "cont." : event.startDate.formatted(date: .omitted, time: .shortened))
                        .font(.callout.monospacedDigit().weight(.medium))
                    Text(endLabel(dayEnd: dayInterval.end))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(width: 70, alignment: .trailing)

                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    if let location = event.location {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if isNow {
                    Text("Now")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.25), in: Capsule())
                }
            }
            .padding(8)
            .background(color.opacity(isNow ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(isPast ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingDetails, arrowEdge: .leading) { EventDetailView(event: event) { showingDetails = false } }
        .accessibilityLabel(accessibilityText)
    }

    private func endLabel(dayEnd: Date) -> String {
        if event.endDate > dayEnd {
            return "→ " + event.endDate.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return event.endDate.formatted(date: .omitted, time: .shortened)
    }

    private var accessibilityText: String {
        let range = DateIntervalFormatter.shortTime.string(from: event.startDate, to: event.endDate)
        var parts = [event.title, range, event.calendarTitle]
        if let location = event.location { parts.append(location) }
        return parts.joined(separator: ", ")
    }
}

/// Read-only details, with Edit for events DeskDash can change.
struct EventDetailView: View {
    let event: CalendarEvent
    let dismiss: () -> Void
    @State private var isEditing = false

    var body: some View {
        if isEditing {
            EventEditorView(mode: .edit(event), draft: EventDraft(event: event), dismiss: dismiss)
        } else {
            details
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(event.calendarColor?.color ?? .accentColor)
                    .frame(width: 10, height: 10)
                Text(event.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(timeText, systemImage: "clock")
            Label(event.calendarTitle, systemImage: "calendar")
            if let summary = event.repeatRule.summary {
                Label(summary, systemImage: "repeat")
            }
            if let location = event.location {
                Label(location, systemImage: "mappin.and.ellipse")
                    .textSelection(.enabled)
            }
            if let notes = event.notes {
                Divider()
                ScrollView {
                    Text(notes)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
            Divider()
            if let reason = event.readOnlyReason {
                Label(reason, systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack {
                    Spacer()
                    Button("Edit…") { isEditing = true }
                        .keyboardShortcut("e")
                }
            }
        }
        .font(.callout)
        .padding(16)
        .frame(width: 300, alignment: .leading)
    }

    private var timeText: String {
        if event.isAllDay {
            let calendar = Calendar.autoupdatingCurrent
            let lastDay = calendar.date(byAdding: .second, value: -1, to: event.endDate) ?? event.startDate
            if calendar.isDate(event.startDate, inSameDayAs: lastDay) {
                return event.startDate.formatted(.dateTime.weekday(.wide).day().month(.wide)) + " · All day"
            }
            return DateIntervalFormatter.longDate.string(from: event.startDate, to: lastDay) + " · All day"
        }
        return DateIntervalFormatter.fullDateTime.string(from: event.startDate, to: event.endDate)
    }
}

extension DateIntervalFormatter {
    @MainActor static let shortTime: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    @MainActor static let longDate: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    @MainActor static let fullDateTime: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
