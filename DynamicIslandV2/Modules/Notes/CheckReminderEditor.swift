import SwiftUI

struct CheckReminderDraft: Identifiable {
    let id = UUID()
    let noteID: UUID
    let check: NoteEntry.Check
    let isNew: Bool
}

struct CheckReminderEditor: View {
    let draft: CheckReminderDraft
    let isConnected: Bool
    let onSave: (String, ReminderTiming?) -> Void
    let onCancel: () -> Void
    @State private var text: String
    @State private var hasDue: Bool
    @State private var date: Date
    @State private var hasTime: Bool
    @State private var lead: Int
    @State private var customMinutes: Int
    @State private var timingEdited = false

    private static let leads = [0, 5, 15, 30, 60, 120, 1440, 2880, 10080]

    init(draft: CheckReminderDraft, isConnected: Bool,
         onSave: @escaping (String, ReminderTiming?) -> Void, onCancel: @escaping () -> Void) {
        self.draft = draft
        self.isConnected = isConnected
        self.onSave = onSave
        self.onCancel = onCancel
        let timing = draft.check.timing
        _text = State(initialValue: draft.check.text)
        _hasDue = State(initialValue: timing?.due != nil || draft.isNew)
        _date = State(initialValue: timing?.date ?? Date())
        _hasTime = State(initialValue: timing?.hasTime ?? false)
        let minutes = timing?.leadMinutes ?? -1
        _lead = State(initialValue: Self.leads.contains(minutes) || minutes == -1 ? minutes : -2)
        _customMinutes = State(initialValue: max(1, minutes))
    }

    private var proposedTiming: ReminderTiming? {
        // Opening an existing reminder must not rewrite imported alarms or time zones.
        if !draft.isNew && !timingEdited { return draft.check.timing }
        guard hasDue else { return nil }
        return .make(date: date, hasTime: hasTime, leadMinutes: lead == -1 ? nil : (lead == -2 ? customMinutes : lead))
    }

    private var pastAlert: Bool {
        guard draft.isNew || timingEdited, let alert = proposedTiming?.notificationDate else { return false }
        return alert <= Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.isNew ? "Nuovo promemoria" : "Modifica promemoria").font(.headline)
            TextField("Cosa devi fare?", text: $text).textFieldStyle(.roundedBorder)
            Toggle("Data di scadenza", isOn: $hasDue)
            if hasDue {
                DatePicker("Scadenza", selection: $date, displayedComponents: .date)
                Toggle("Specifica un’ora", isOn: $hasTime)
                if hasTime { DatePicker("Ora", selection: $date, displayedComponents: .hourAndMinute) }
                Picker("Notifica", selection: $lead) {
                    Text("Nessuna").tag(-1)
                    Text(hasTime ? "Alla scadenza" : "Il giorno stesso alle 09:00").tag(0)
                    Text("5 minuti prima").tag(5)
                    Text("15 minuti prima").tag(15)
                    Text("30 minuti prima").tag(30)
                    Text("1 ora prima").tag(60)
                    Text("2 ore prima").tag(120)
                    Text("1 giorno prima").tag(1440)
                    Text("2 giorni prima").tag(2880)
                    Text("1 settimana prima").tag(10080)
                    Text("Anticipo personalizzato…").tag(-2)
                }
                if lead == -2 {
                    HStack {
                        Text("Minuti prima")
                        TextField("Minuti", value: $customMinutes, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 90)
                    }
                }
                if !hasTime && lead != -1 {
                    Text("Senza un’ora di scadenza, l’anticipo si calcola dalle 09:00 del giorno scelto.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let alert = proposedTiming?.notificationDate {
                Label(alert.formatted(date: .abbreviated, time: .shortened), systemImage: "bell")
                    .font(.caption)
            }
            if pastAlert {
                Text("La notifica cadrebbe nel passato. Scegli una data, un’ora o un anticipo diverso.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text(isConnected
                 ? "La notifica verrà gestita da Promemoria Apple. Abilita le sue notifiche sull’iPhone."
                 : "Per ricevere notifiche, collega questa checklist a Promemoria usando l’icona accanto al titolo.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Annulla", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button(draft.isNew ? "Aggiungi" : "Salva") {
                    onSave(text.trimmingCharacters(in: .whitespacesAndNewlines), proposedTiming)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pastAlert || (hasDue && lead == -2 && !(1...525600).contains(customMinutes)))
            }
        }
        .font(.system(size: 12)).padding(16).frame(width: 350)
        .onChange(of: hasDue) { _, _ in timingEdited = true }
        .onChange(of: date) { _, _ in timingEdited = true }
        .onChange(of: hasTime) { _, _ in timingEdited = true }
        .onChange(of: lead) { _, _ in timingEdited = true }
        .onChange(of: customMinutes) { _, _ in timingEdited = true }
    }
}
