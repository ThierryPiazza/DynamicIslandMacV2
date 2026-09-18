import AppKit
import EventKit

struct RemindersAccount: Identifiable {
    let id: String
    let title: String
    let isLocal: Bool
}

struct RemindersLink: Codable, Equatable {
    var calendarID: String
    var calendarTitle: String
    var noteTitle: String
    var baseline: [NoteEntry.Check] = []
    var reminderIDs: [String: String] = [:]
}

/// Field-by-field three-way merge. Local changes win only on the same field;
/// an iPhone completion must survive a simultaneous title edit on the Mac.
enum RemindersMerge {
    static func merge(local: [NoteEntry.Check], remote: [NoteEntry.Check],
                      baseline: [NoteEntry.Check]) -> [NoteEntry.Check] {
        let old = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
        let incoming = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        var result: [NoteEntry.Check] = []
        for var check in local {
            if let previous = old[check.id] {
                guard let other = incoming[check.id] else {
                    // A remote deletion wins unless there is an unsynced local edit.
                    if check != previous { result.append(check) }
                    continue
                }
                if check.text == previous.text { check.text = other.text }
                if check.done == previous.done { check.done = other.done }
                // Treat deadline + alert as one setting to keep their relationship.
                if check.timing == previous.timing { check.timing = other.timing }
            }
            result.append(check)
        }
        let localIDs = Set(local.map(\.id))
        // A locally deleted item stays deleted; new iPhone items are imported.
        result += remote.filter { !localIDs.contains($0.id) && old[$0.id] == nil }
        return result
    }
}

final class RemindersBridge {
    struct Snapshot {
        let calendar: EKCalendar
        let reminders: [EKReminder]
        let revision: Int
    }

    enum Failure: LocalizedError {
        case permission, missingList, unavailable, stale
        var errorDescription: String? {
            switch self {
            case .permission: return "Consenti l’accesso in Impostazioni di Sistema → Privacy e sicurezza → Promemoria, poi riprova."
            case .missingList: return "Lista non disponibile o non modificabile. Controlla l’account in Promemoria; se la lista è stata eliminata, scollega e ricollega la checklist."
            case .unavailable: return "Promemoria non disponibile. Nessun appunto locale è stato cancellato. Riprova."
            case .stale: return "Promemoria sta cambiando. Aggiornamento in corso…"
            }
        }
    }

    private let store = EKEventStore()
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var revision = 0
    var onChange: (() -> Void)?

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        timer?.invalidate()
    }

    func startObserving() {
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.revision += 1
            self?.onChange?()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onChange?()
        })
        // EventKit changes and foreground activation are primary; polling is a fallback.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.onChange?() }
        timer?.tolerance = 30
    }

    private func requireAccess() throws {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { throw Failure.permission }
    }

    func authorize(completion: @escaping (Result<[RemindersAccount], Error>) -> Void) {
        store.requestFullAccessToReminders { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else { completion(.failure(error ?? Failure.permission)); return }
                let sources = self.store.calendars(for: .reminder)
                    .filter(\.allowsContentModifications).compactMap(\.source)
                var seen = Set<String>()
                let accounts = sources.filter { seen.insert($0.sourceIdentifier).inserted }.map {
                    RemindersAccount(id: $0.sourceIdentifier, title: $0.title, isLocal: $0.sourceType == .local)
                }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                completion(.success(accounts))
            }
        }
    }

    func createList(for note: NoteEntry, account: RemindersAccount) throws -> RemindersLink {
        try requireAccess()
        guard let source = store.sources.first(where: { $0.sourceIdentifier == account.id }) else { throw Failure.unavailable }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Island – \(note.displayTitle)"
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return RemindersLink(calendarID: calendar.calendarIdentifier, calendarTitle: calendar.title, noteTitle: note.title)
    }

    func fetch(link: RemindersLink, completion: @escaping (Result<Snapshot, Error>) -> Void) {
        do {
            try requireAccess()
            guard let calendar = store.calendar(withIdentifier: link.calendarID), calendar.allowsContentModifications else { throw Failure.missingList }
            let currentRevision = revision
            let predicate = store.predicateForReminders(in: [calendar])
            store.fetchReminders(matching: predicate) { [weak self] reminders in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard self.revision == currentRevision else {
                        self.onChange?()
                        completion(.failure(Failure.stale)); return
                    }
                    guard let reminders else { completion(.failure(Failure.unavailable)); return }
                    completion(.success(Snapshot(calendar: calendar, reminders: reminders, revision: currentRevision)))
                }
            }
        } catch { completion(.failure(error)) }
    }

    func reconcile(_ note: NoteEntry, snapshot: Snapshot) throws -> NoteEntry {
        try requireAccess()
        guard var link = note.remindersLink, snapshot.revision == revision else { throw Failure.stale }
        var updated = note
        var byID: [UUID: EKReminder] = [:]
        var remote: [NoteEntry.Check] = []
        // Stable URL markers also recover item identity after an iCloud identifier
        // change or a crash between the EventKit commit and saving local metadata.
        for reminder in snapshot.reminders.sorted(by: { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }) {
            let marker = reminder.url
            let markedID = marker?.scheme == "opennotch-reminder" && marker?.host == note.id.uuidString.lowercased()
                ? UUID(uuidString: marker!.lastPathComponent) : nil
            let savedID = link.reminderIDs.first(where: { $0.value == reminder.calendarItemIdentifier }).flatMap { UUID(uuidString: $0.key) }
            var id = markedID ?? savedID ?? UUID()
            // Duplicated reminders can have the same URL; preserve both as separate items.
            if byID[id] != nil { id = UUID() }
            byID[id] = reminder
            remote.append(.init(id: id, text: reminder.title ?? "", done: reminder.isCompleted, timing: ReminderTiming.read(reminder)))
        }
        updated.checks = RemindersMerge.merge(local: note.checks, remote: remote, baseline: link.baseline)
        if note.title != link.noteTitle {
            snapshot.calendar.title = "Island – \(note.displayTitle)"
        } else if snapshot.calendar.title != link.calendarTitle {
            let title = snapshot.calendar.title
            updated.title = title.hasPrefix("Island – ") ? String(title.dropFirst("Island – ".count)) : title
        }

        var changed = false
        do {
            if snapshot.calendar.title != link.calendarTitle && note.title != link.noteTitle {
                try store.saveCalendar(snapshot.calendar, commit: false)
                changed = true
            }
            let kept = Set(updated.checks.map(\.id))
            for (id, reminder) in byID where !kept.contains(id) {
                try store.remove(reminder, commit: false)
                changed = true
            }
            var savedReminders: [UUID: EKReminder] = [:]
            for check in updated.checks {
                let reminder = byID[check.id] ?? EKReminder(eventStore: store)
                let marker = URL(string: "opennotch-reminder://\(note.id.uuidString.lowercased())/\(check.id.uuidString)")!
                // Preserve a URL the user added in Apple Reminders. Existing item
                // identifiers still associate that reminder with its local check.
                let desiredURL = reminder.url == nil || reminder.url?.scheme == "opennotch-reminder" ? marker : reminder.url
                if byID[check.id] == nil || reminder.title != check.text || reminder.isCompleted != check.done || reminder.url != desiredURL || ReminderTiming.read(reminder) != check.timing {
                    reminder.calendar = snapshot.calendar
                    reminder.title = check.text
                    reminder.isCompleted = check.done
                    reminder.url = desiredURL
                    ReminderTiming.apply(check.timing, to: reminder)
                    try store.save(reminder, commit: false)
                    changed = true
                }
                savedReminders[check.id] = reminder
            }
            if changed { try store.commit() }
            link.reminderIDs = Dictionary(uniqueKeysWithValues: savedReminders.map { ($0.key.uuidString, $0.value.calendarItemIdentifier) })
            link.baseline = updated.checks
            link.calendarTitle = snapshot.calendar.title
            link.noteTitle = updated.title
            updated.remindersLink = link
            if updated.checks != note.checks || updated.title != note.title { updated.modified = Date() }
            return updated
        } catch {
            // Discard staged writes, keeping the local baseline for the next retry.
            store.reset()
            throw error
        }
    }
}
