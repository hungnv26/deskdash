import SwiftUI

struct MonthGridView: View {
    @Environment(CalendarStore.self) private var calendar

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let math = calendar.math
        let days = calendar.gridDays
        let eventsByDay = calendar.eventsByDay

        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Array(math.orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            GeometryReader { proxy in
                let rowHeight = max((proxy.size.height - 5 * 4) / 6, 28)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(days, id: \.self) { day in
                        DayCell(
                            day: day,
                            events: eventsByDay[math.startOfDay(day)] ?? [],
                            isToday: math.isSameDay(day, calendar.today),
                            isSelected: math.isSameDay(day, calendar.selectedDate),
                            isInMonth: math.isSameMonth(day, calendar.displayedMonth)
                        ) {
                            calendar.select(day)
                        } newEvent: {
                            calendar.select(day)
                            calendar.newEventRequest += 1
                        }
                        .frame(height: rowHeight)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DayCell: View {
    let day: Date
    let events: [CalendarEvent]
    let isToday: Bool
    let isSelected: Bool
    let isInMonth: Bool
    let select: () -> Void
    var newEvent: () -> Void = {}

    private var dotColors: [Color] {
        var seen = Set<String>()
        var colors: [Color] = []
        for event in events where seen.insert(event.calendarID).inserted {
            colors.append(event.calendarColor?.color ?? .accentColor)
            if colors.count == 3 { break }
        }
        return colors
    }

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.day()))
                    .font(.callout.monospacedDigit().weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.accentColor : (isInMonth ? Color.primary : Color.secondary.opacity(0.6)))
                    .frame(width: 28, height: 28)
                    .overlay {
                        // Today is a hollow ring so the wallpaper shows through.
                        if isToday { Circle().strokeBorder(Color.accentColor, lineWidth: 2) }
                    }
                HStack(spacing: 3) {
                    ForEach(Array(dotColors.enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
                .opacity(isInMonth ? 1 : 0.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                // The selected day is outlined, not filled.
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("New Event on This Day") { newEvent() }
        }
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityText: String {
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let count = events.count
        let suffix = count == 0 ? "no events" : (count == 1 ? "1 event" : "\(count) events")
        return "\(date)\(isToday ? ", today" : ""), \(suffix)"
    }
}
