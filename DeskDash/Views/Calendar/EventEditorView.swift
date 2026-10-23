import SwiftUI

/// Creates or edits an event. Nothing is written until Save.
struct EventEditorView: View {
    enum Mode {
        case create
        case edit(CalendarEvent)
    }

    let mode: Mode
    let dismiss: () -> Void

    @Environment(CalendarStore.self) private var store
    @State private var draft: EventDraft
    @State private var span: EventSpan = .thisEvent
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var titleFocused: Bool
    private let original: EventDraft

    init(mode: Mode, draft: EventDraft, dismiss: @escaping () -> Void) {
        self.mode = mode
        self.dismiss = dismiss
        self.original = draft
        _draft = State(initialValue: draft)
    }

    private var editedEvent: CalendarEvent? {
        if case .edit(let event) = mode { return event }
        return nil
    }

    private var validation: String? { draft.validationMessage() }
    private var repeatChanged: Bool { draft.repeatRule != original.repeatRule }

    /// Custom is only offered when the event already has a custom pattern.
    private var repeatChoices: [RepeatFrequency] {
        original.repeatRule.frequency == .custom ? RepeatFrequency.editable + [.custom] : RepeatFrequency.editable
    }

    private var endsOnDate: Binding<Bool> {
        Binding(
            get: { draft.repeatRule.endDate != nil },
            set: { onDate in draft.repeatRule.endDate = onDate ? defaultRepeatEnd() : nil }
        )
    }

    private var repeatEndDate: Binding<Date> {
        Binding(
            get: { draft.repeatRule.endDate ?? draft.start },
            set: { draft.repeatRule.endDate = $0 }
        )
    }

    /// A sensible first guess for "On Date", scaled to how often it repeats.
    private func defaultRepeatEnd() -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let step: DateComponents
        switch draft.repeatRule.frequency {
        case .daily: step = DateComponents(month: 1)
        case .weekly, .biweekly: step = DateComponents(month: 3)
        case .monthly: step = DateComponents(year: 1)
        default: step = DateComponents(year: 5)
        }
        return calendar.date(byAdding: step, to: draft.start) ?? draft.start
    }
    private var hasChanges: Bool { editedEvent == nil || draft != original }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editedEvent == nil ? "New Event" : "Edit Event")
                .font(.headline)

            TextField("Title", text: $draft.title)
                .textFieldStyle(.roundedBorder)
                .font(.body.weight(.medium))
                .focused($titleFocused)
                .onSubmit(save)
            TextField("Location", text: $draft.location)
                .textFieldStyle(.roundedBorder)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("All-day")
                    Toggle("All-day", isOn: $draft.isAllDay)
                        .labelsHidden()
                }
                GridRow {
                    Text("Starts")
                    DatePicker("Starts", selection: $draft.start, displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                        .labelsHidden()
                }
                GridRow {
                    Text("Ends")
                    DatePicker("Ends", selection: $draft.end, displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                        .labelsHidden()
                }
                GridRow {
                    Text("Calendar")
                    Picker("Calendar", selection: $draft.calendarID) {
                        ForEach(store.writableCalendars) { calendar in
                            Label {
                                Text(calendar.title)
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(calendar.color?.color ?? .accentColor)
                            }
                            .tag(calendar.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    Text("Repeat")
                    Picker("Repeat", selection: $draft.repeatRule.frequency) {
                        ForEach(repeatChoices) { frequency in
                            Text(frequency.title).tag(frequency)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help(draft.repeatRule.frequency == .custom ? "This event repeats in a pattern DeskDash keeps as is. Pick another option to replace it." : "")
                }
                if draft.repeatRule.repeats && draft.repeatRule.frequency != .custom {
                    GridRow {
                        Text("End Repeat")
                        HStack(spacing: 8) {
                            Picker("End Repeat", selection: endsOnDate) {
                                Text("Never").tag(false)
                                Text("On Date").tag(true)
                            }
                            .labelsHidden()
                            .fixedSize()
                            if draft.repeatRule.endDate != nil {
                                DatePicker("Repeat ends", selection: repeatEndDate, in: draft.start..., displayedComponents: .date)
                                    .labelsHidden()
                            }
                        }
                    }
                }
                if editedEvent?.isRecurring == true {
                    GridRow {
                        Text("Apply to")
                        if repeatChanged {
                            Text("This and future events")
                                .foregroundStyle(.secondary)
                                .help("Changing how an event repeats applies to this and future events.")
                        } else {
                            Picker("Apply to", selection: $span) {
                                ForEach(EventSpan.allCases) { span in
                                    Text(span.title).tag(span)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
            }

            TextField("Notes", text: $draft.notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            if let message = errorMessage ?? (draft.title.isEmpty ? nil : validation) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "Saving…" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(validation != nil || isSaving || !hasChanges)
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear { titleFocused = true }
        .onChange(of: draft.repeatRule.frequency) { _, frequency in
            if frequency == .never || frequency == .custom { draft.repeatRule.endDate = nil }
        }
        // Moving the start keeps the event's length, like Calendar does.
        .onChange(of: draft.start) { oldValue, newValue in
            let duration = max(draft.end.timeIntervalSince(oldValue), 0)
            draft.end = newValue.addingTimeInterval(duration)
        }
    }

    private func save() {
        guard validation == nil, !isSaving, hasChanges else { return }
        isSaving = true
        errorMessage = nil
        Task {
            let error: String?
            if let event = editedEvent {
                error = await store.updateEvent(event, from: original, to: draft, span: span)
            } else {
                error = await store.createEvent(draft)
            }
            isSaving = false
            if let error {
                errorMessage = error
            } else {
                dismiss()
            }
        }
    }
}
