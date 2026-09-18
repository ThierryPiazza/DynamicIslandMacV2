import Foundation
import Combine

struct NoteEntry: Identifiable, Codable, Equatable {
    struct Check: Identifiable, Codable, Equatable {
        var id = UUID()
        var text: String
        var done = false
        var timing: ReminderTiming?
    }
    var id = UUID()
    var title = ""
    var body = ""
    var pinned = false
    var isChecklist = false
    var checks: [Check] = []
    var modified = Date()
    var remindersLink: RemindersLink?

    var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Senza titolo" : title }
}

final class NotesStore: ObservableObject {
    @Published private(set) var notes: [NoteEntry]
    @Published private(set) var deletedNote: NoteEntry?
    @Published var storageMessage: String?
    @Published var remindersMessage = ""
    @Published private(set) var remindersAccounts: [RemindersAccount] = []
    @Published private(set) var remindersBusy = false
    private let defaults: UserDefaults
    private let key = "notes.collection.v2"
    private let usesReminders: Bool
    private lazy var reminders = RemindersBridge()
    private var syncWork: DispatchWorkItem?
    private var syncing = false
    private var syncAgain = false

    init(defaults: UserDefaults = .standard, usesReminders: Bool = true) {
        self.defaults = defaults
        self.usesReminders = usesReminders
        if let data = defaults.data(forKey: key) {
            do { notes = try JSONDecoder().decode([NoteEntry].self, from: data) }
            catch {
                // Keep the original bytes for recovery instead of overwriting them
                // with a scratchpad migration when a saved collection cannot decode.
                let recoveryKey = "notes.recovery.v1"
                if let previous = defaults.data(forKey: recoveryKey), previous != data {
                    defaults.set(previous, forKey: "notes.recovery.\(UUID().uuidString)")
                }
                defaults.set(data, forKey: recoveryKey)
                notes = []
                storageMessage = "Non è stato possibile leggere gli appunti salvati. Una copia dei dati originali è stata conservata per il recupero."
            }
        } else {
            let old = defaults.string(forKey: "notes.scratchpad.v1") ?? ""
            notes = old.isEmpty ? [] : [NoteEntry(title: "I miei appunti", body: old)]
            save()
        }
        if usesReminders && notes.contains(where: { $0.remindersLink != nil }) {
            observeReminders()
            refreshReminders()
        }
    }

    func filtered(_ query: String) -> [NoteEntry] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.filter { note in
            term.isEmpty || ([note.title, note.body] + note.checks.map(\.text))
                .contains { $0.localizedStandardContains(term) }
        }.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.modified > $1.modified
        }
    }

    @discardableResult
    func add(checklist: Bool = false) -> UUID {
        let note = NoteEntry(isChecklist: checklist)
        notes.insert(note, at: 0)
        save()
        return note.id
    }

    func update(_ id: UUID, _ change: (inout NoteEntry) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var updated = notes[index]
        change(&updated)
        guard updated != notes[index] else { return }
        updated.modified = Date()
        notes[index] = updated
        save()
    }

    func remove(_ id: UUID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        deletedNote = note
        notes.removeAll { $0.id == id }
        save()
    }

    func undoDelete() {
        guard let note = deletedNote else { return }
        notes.append(note)
        deletedNote = nil
        save()
    }

    private func save(scheduleSync: Bool = true) {
        if let data = try? JSONEncoder().encode(notes) { defaults.set(data, forKey: key) }
        if scheduleSync { refreshReminders() }
    }

    func prepareReminders() {
        guard usesReminders, !remindersBusy else { return }
        remindersBusy = true
        remindersMessage = ""
        reminders.authorize { [weak self] result in
            guard let self else { return }
            self.remindersBusy = false
            switch result {
            case .success(let accounts):
                self.remindersAccounts = accounts
                if accounts.isEmpty {
                    self.remindersMessage = "Nessun account disponibile. Attiva Promemoria in iCloud sul Mac e crea una lista nell’app Promemoria, poi riprova."
                }
            case .failure(let error): self.remindersMessage = error.localizedDescription
            }
        }
    }

    func connectReminders(_ id: UUID, account: RemindersAccount) {
        guard let index = notes.firstIndex(where: { $0.id == id && $0.isChecklist }),
              notes[index].remindersLink == nil, !remindersBusy else { return }
        do {
            let link = try reminders.createList(for: notes[index], account: account)
            notes[index].remindersLink = link
            observeReminders()
            save()
            remindersMessage = "Lista «\(link.calendarTitle)» creata in \(account.title)."
        } catch { remindersMessage = error.localizedDescription }
    }

    func disconnectReminders(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].remindersLink = nil
        save()
        remindersMessage = "Collegamento rimosso. La lista rimane in Promemoria."
    }

    private func observeReminders() {
        reminders.onChange = { [weak self] in self?.refreshReminders() }
        reminders.startObserving()
    }

    deinit { syncWork?.cancel() }

    func refreshReminders() {
        guard usesReminders, notes.contains(where: { $0.remindersLink != nil }) else { return }
        syncWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.syncReminders() }
        syncWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func syncReminders() {
        if syncing { syncAgain = true; return }
        let ids = notes.filter { $0.remindersLink != nil }.map(\.id)
        guard !ids.isEmpty else { return }
        syncing = true
        remindersBusy = true
        syncNext(ids, errors: [])
    }

    private func syncNext(_ ids: [UUID], errors: [String]) {
        guard let id = ids.first else {
            syncing = false
            remindersBusy = false
            remindersMessage = errors.isEmpty ? "Promemoria aggiornati sul Mac. iCloud sincronizza con l’iPhone." : errors.joined(separator: "\n")
            if syncAgain { syncAgain = false; refreshReminders() }
            return
        }
        guard let note = notes.first(where: { $0.id == id }), let link = note.remindersLink else {
            syncNext(Array(ids.dropFirst()), errors: errors); return
        }
        reminders.fetch(link: link) { [weak self] result in
            guard let self else { return }
            var errors = errors
            // Fetch is asynchronous: always merge against the latest local edits.
            if let index = self.notes.firstIndex(where: { $0.id == id }),
               self.notes[index].remindersLink?.calendarID == link.calendarID {
                do {
                    let snapshot = try result.get()
                    let updated = try self.reminders.reconcile(self.notes[index], snapshot: snapshot)
                    if self.notes[index] != updated {
                        self.notes[index] = updated
                        self.save(scheduleSync: false)
                    }
                } catch {
                    errors.append("\(note.displayTitle): \(error.localizedDescription)")
                }
            }
            self.syncNext(Array(ids.dropFirst()), errors: errors)
        }
    }
}
