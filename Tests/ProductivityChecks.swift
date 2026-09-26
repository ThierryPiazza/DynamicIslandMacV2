import AppKit
import ImageIO
import UniformTypeIdentifiers
import EventKit
import PDFKit

@main
struct ProductivityChecks {
    @MainActor
    static func main() async throws {
        let suite = "DynamicIsland.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try checkNotes(defaults)
        try checkRemindersMerge()
        try checkReminderTiming()
        checkClipboard(defaults)
        checkTabs(defaults)
        checkPomodoro()
        try checkFiles()
        try await checkExportSafety()
        print("PASS: migrazione e ricerca note, checklist, preferiti persistenti, ordine/visibilità/swipe, Pomodoro e file senza sovrascrittura.")
    }

    static func checkNotes(_ defaults: UserDefaults) throws {
        defaults.set("Appunti precedenti: caffè ☕", forKey: "notes.scratchpad.v1")
        let notes = NotesStore(defaults: defaults, usesReminders: false)
        precondition(notes.notes.count == 1 && notes.notes[0].body.contains("caffè"))
        let id = notes.add(checklist: true)
        notes.update(id) { $0.title = "Spesa"; $0.pinned = true; $0.checks = [.init(text: "Caffè", done: true), .init(text: "Pane")] }
        precondition(notes.filtered("").first?.id == id)
        precondition(notes.filtered("pane").count == 1)
        precondition(notes.filtered("CAFFE").count == 2)
        let reopened = NotesStore(defaults: defaults, usesReminders: false)
        precondition(reopened.notes.first(where: { $0.id == id })?.checks.first?.done == true)
        notes.remove(id)
        precondition(notes.notes.count == 1)
        notes.undoDelete()
        precondition(notes.notes.count == 2)
        for note in notes.notes { notes.remove(note.id) }
        precondition(NotesStore(defaults: defaults, usesReminders: false).notes.isEmpty, "Non ripetere la migrazione dopo eliminazione volontaria")
        precondition(defaults.string(forKey: "notes.scratchpad.v1")?.contains("caffè") == true)
        let corrupt = Data("unreadable".utf8)
        defaults.set(corrupt, forKey: "notes.collection.v2")
        let recovered = NotesStore(defaults: defaults, usesReminders: false)
        precondition(recovered.notes.isEmpty && recovered.storageMessage != nil)
        precondition(defaults.data(forKey: "notes.recovery.v1") == corrupt)
        _ = recovered.add()
        precondition(defaults.data(forKey: "notes.recovery.v1") == corrupt)
        recovered.update(recovered.notes[0].id) { $0.title = "Titolo" }
        let modified = recovered.notes[0].modified
        recovered.update(recovered.notes[0].id) { $0.title = "Titolo" }
        precondition(recovered.notes[0].modified == modified, "No-op edits do not trigger saves or sync")
    }

    static func checkRemindersMerge() throws {
        let original = NoteEntry.Check(text: "Studiare matematica")
        var local = original
        local.text = "Studiare capitolo 3"
        var phone = original
        phone.done = true
        let combined = RemindersMerge.merge(local: [local], remote: [phone], baseline: [original])
        precondition(combined.count == 1 && combined[0].text == local.text && combined[0].done,
                     "Una modifica al testo sul Mac non deve annullare la spunta dell’iPhone")
        precondition(RemindersMerge.merge(local: [original], remote: [], baseline: [original]).isEmpty,
                     "Eliminazione da iPhone importata")
        precondition(RemindersMerge.merge(local: [], remote: [phone], baseline: [original]).isEmpty,
                     "Una voce eliminata sul Mac non ricompare")
        precondition(RemindersMerge.merge(local: [local], remote: [], baseline: [original]) == [local],
                     "Conserva una modifica locale non sincronizzata se la voce remota sparisce")
        let added = NoteEntry.Check(text: "Portare il libro")
        precondition(RemindersMerge.merge(local: [original], remote: [phone, added], baseline: [original]) == [phone, added])
        var remoteConflict = original
        remoteConflict.text = "Titolo da iPhone"
        precondition(RemindersMerge.merge(local: [local], remote: [remoteConflict], baseline: [original]) == [local])
        precondition(RemindersMerge.merge(local: [original], remote: [remoteConflict], baseline: [original]) == [remoteConflict])
        precondition(RemindersMerge.merge(local: [original], remote: [], baseline: []) == [original],
                     "La prima sincronizzazione esporta le voci esistenti")
        precondition(RemindersMerge.merge(local: combined, remote: combined, baseline: combined) == combined,
                     "La sincronizzazione ripetuta è idempotente")
        var unchecked = phone
        unchecked.done = false
        precondition(RemindersMerge.merge(local: [phone], remote: [unchecked], baseline: [phone]) == [unchecked])
        precondition(RemindersMerge.merge(local: [original], remote: [original], baseline: []).count == 1,
                     "Recuperare un commit prima del salvataggio locale non duplica la voce")

        let suite = "DynamicIsland.Reminders.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NotesStore(defaults: defaults, usesReminders: false)
        let id = store.add(checklist: true)
        let link = RemindersLink(calendarID: "test-list", calendarTitle: "Island – Scuola", noteTitle: "Scuola",
                                 baseline: [original], reminderIDs: [original.id.uuidString: "test-reminder"])
        store.update(id) { $0.title = "Scuola"; $0.checks = [original]; $0.remindersLink = link }
        let reopened = NotesStore(defaults: defaults, usesReminders: false)
        precondition(reopened.notes.first?.remindersLink == link, "Baseline e identità sopravvivono al riavvio")
        reopened.remove(id)
        reopened.undoDelete()
        precondition(reopened.notes.first?.remindersLink == link)
        reopened.disconnectReminders(id)
        precondition(reopened.notes.first?.remindersLink == nil && reopened.notes.first?.checks == [original])
        precondition(NotesStore(defaults: defaults, usesReminders: false).notes.first?.remindersLink == nil)
        // Missing optional metadata must remain compatible with notes saved before this feature.
        let legacy = Data("{\"title\":\"Vecchia checklist\",\"body\":\"\",\"pinned\":false,\"isChecklist\":true,\"checks\":[],\"modified\":0,\"id\":\"\(UUID().uuidString)\"}".utf8)
        let decoded = try JSONDecoder().decode(NoteEntry.self, from: legacy)
        precondition(decoded.remindersLink == nil)
        print("PASS: Promemoria — merge bidirezionale, conflitti, eliminazioni, nuove voci, riavvio e scollegamento.")
    }

    static func checkReminderTiming() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let due = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 10, minute: 30))!
        let timing = ReminderTiming.make(date: due, hasTime: true, leadMinutes: 30, calendar: calendar)
        precondition(timing.date == due && timing.due?.hour == 10)
        precondition(timing.notificationDate == due.addingTimeInterval(-1800))
        let dayBefore = ReminderTiming.make(date: due, hasTime: true, leadMinutes: 1440, calendar: calendar)
        precondition(calendar.component(.hour, from: dayBefore.notificationDate!) == 10)
        precondition(calendar.component(.day, from: dayBefore.notificationDate!) == 28)
        precondition(dayBefore.leadMinutes == 1440, "Un giorno prima resta alla stessa ora anche al cambio dell’ora")
        let dateOnly = ReminderTiming.make(date: due, hasTime: false, leadMinutes: 0)
        precondition(dateOnly.due?.hour == nil && dateOnly.due?.minute == nil)
        precondition(Calendar.current.component(.hour, from: dateOnly.notificationDate!) == 9)
        precondition(ReminderTiming.make(date: due, hasTime: true, leadMinutes: nil).notificationDate == nil)
        let decoded = try JSONDecoder().decode(ReminderTiming.self, from: JSONEncoder().encode(timing))
        precondition(decoded == timing)

        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        ReminderTiming.apply(timing, to: reminder)
        precondition(ReminderTiming.read(reminder) == timing)
        precondition(reminder.startDateComponents != nil && reminder.alarms?.count == 1)
        ReminderTiming.apply(timing, to: reminder)
        precondition(reminder.alarms?.count == 1, "Niente notifiche duplicate")
        reminder.addAlarm(EKAlarm(absoluteDate: due.addingTimeInterval(-60)))
        ReminderTiming.apply(timing, to: reminder)
        precondition(reminder.alarms?.count == 2, "Le modifiche al testo preservano gli avvisi aggiunti sull’iPhone")
        ReminderTiming.apply(nil, to: reminder)
        precondition(reminder.dueDateComponents == nil && (reminder.alarms ?? []).isEmpty)
        ReminderTiming.apply(dateOnly, to: reminder)
        precondition(reminder.dueDateComponents?.hour == nil && ReminderTiming.read(reminder) == dateOnly)

        let old = NoteEntry.Check(text: "Compito")
        var phone = old
        phone.timing = timing
        var local = old
        local.done = true
        let merged = RemindersMerge.merge(local: [local], remote: [phone], baseline: [old])[0]
        precondition(merged.done && merged.timing == timing)
        var changed = phone
        changed.timing = dayBefore
        precondition(RemindersMerge.merge(local: [changed], remote: [phone], baseline: [old])[0].timing == dayBefore)
        let legacyCheck = Data("{\"id\":\"\(UUID().uuidString)\",\"text\":\"Prima\",\"done\":false}".utf8)
        let legacy = try JSONDecoder().decode(NoteEntry.Check.self, from: legacyCheck)
        precondition(legacy.timing == nil)
        print("PASS: scadenze, ora facoltativa, anticipo, cambio ora, EventKit, compatibilità e merge notifiche.")
    }

    static func checkExportSafety() async throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("DynamicIsland-exports-\(UUID().uuidString)")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let source = directory.appendingPathComponent("original.png")
        let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!
        let writer = CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, image, [kCGImagePropertyOrientation: 1] as CFDictionary)
        precondition(CGImageDestinationFinalize(writer))
        let original = try Data(contentsOf: source)
        let converter = FileConverter(outputDirectory: directory)
        let first = try await converter.convert(url: source, toExt: "jpg")
        let firstData = try Data(contentsOf: first)
        let second = try await converter.convert(url: source, toExt: "jpg")
        precondition(first != second && fm.fileExists(atPath: second.path))
        let unchanged = try Data(contentsOf: first)
        let sourceAfter = try Data(contentsOf: source)
        precondition(unchanged == firstData && sourceAfter == original)
        let pdf1 = try await converter.mergePDFs(urls: [source, source])
        let pdf2 = try await converter.mergePDFs(urls: [source, source])
        precondition(pdf1 != pdf2)
        precondition(PDFDocument(url: pdf1)?.pageCount == 2 && PDFDocument(url: pdf2)?.pageCount == 2)
        do {
            _ = try await converter.convert(url: directory.appendingPathComponent("missing.unknown"), toExt: "jpg")
            preconditionFailure("Unsupported exports must fail")
        } catch {}
        let leftovers = try fm.contentsOfDirectory(atPath: directory.path)
        precondition(!leftovers.contains { $0.hasPrefix(".dynamicisland-") }, "Staging folders are cleaned on success and failure")
        let thumbnail = NSImage.clipboardThumbnail(data: original)!
        precondition(thumbnail.size.width <= 160)
        print("PASS: conversioni e PDF ripetuti senza sovrascrittura, originali intatti, pulizia errori e miniature.")
    }

    static func checkClipboard(_ defaults: UserDefaults) {
        let bounded = ClipboardMonitor(defaults: defaults, startMonitoring: false, memoryBudget: 128)
        let old = ClipboardItem(content: .text(String(repeating: "a", count: 90)), date: .distantPast)
        bounded.prepend(old)
        bounded.prepend(ClipboardItem(content: old.content, date: Date()))
        precondition(bounded.items.first?.id == old.id && bounded.items.first?.date != .distantPast)
        bounded.prepend(ClipboardItem(content: .text(String(repeating: "b", count: 90)), date: Date()))
        precondition(bounded.items.count == 1, "Recent memory budget is enforced")
        let clipboard = ClipboardMonitor(defaults: defaults, startMonitoring: false)
        let favorite = ClipboardItem(content: .text("Codice da conservare"), date: Date())
        clipboard.prepend(favorite)
        clipboard.toggleFavorite(favorite)
        for i in 0..<40 { clipboard.prepend(ClipboardItem(content: .text("Recente \(i)"), date: Date())) }
        precondition(clipboard.items.count == 31)
        precondition(clipboard.filtered(query: "CONSERVARE", favoritesOnly: true).count == 1)
        clipboard.prepend(ClipboardItem(content: favorite.content, date: Date()))
        precondition(clipboard.items.first?.id == favorite.id && clipboard.items.first?.isFavorite == true)
        clipboard.clear()
        precondition(clipboard.items.count == 1)
        let restored = ClipboardMonitor(defaults: defaults, startMonitoring: false)
        precondition(restored.items.count == 1 && restored.items[0].id == favorite.id)
        restored.toggleFavorite(restored.items[0])
        precondition(ClipboardMonitor(defaults: defaults, startMonitoring: false).items.isEmpty)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        // Include il cambio dell'ora: la scadenza segue la giornata, non 24 ore.
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30))!
        let yesterday = ClipboardItem(content: .text("Ieri"), date: midnight.addingTimeInterval(-1))
        let today = ClipboardItem(content: .text("Oggi"), date: midnight)
        let pinned = ClipboardItem(content: .text("Preferito di ieri"), date: midnight.addingTimeInterval(-86400))
        let daily = ClipboardMonitor(defaults: defaults, startMonitoring: false)
        daily.prepend(yesterday)
        daily.prepend(today)
        daily.prepend(pinned)
        daily.toggleFavorite(pinned)
        daily.clearExpiredItems(now: midnight.addingTimeInterval(-0.5), calendar: calendar)
        precondition(daily.items.count == 3)
        daily.clearExpiredItems(now: midnight, calendar: calendar)
        precondition(Set(daily.items.map(\.id)) == Set([today.id, pinned.id]))
        daily.clearExpiredItems(now: midnight.addingTimeInterval(3 * 86400), calendar: calendar)
        precondition(daily.items.count == 1 && daily.items[0].id == pinned.id)
        precondition(ClipboardMonitor(defaults: defaults, startMonitoring: false).items[0].id == pinned.id)
    }

    static func checkTabs(_ defaults: UserDefaults) {
        defaults.set([6, 5, 5, 999, 3], forKey: "mod.tabOrder")
        defaults.set([0, 1, 2, 3, 5, 6, 7], forKey: "mod.hiddenTabs")
        let settings = ModuleSettings(defaults: defaults, usesSystemServices: false)
        precondition(settings.orderedTabs.count == ExpandedTab.allCases.count && settings.orderedTabs.first == .timer)
        precondition(settings.visibleTabs == [.timer], "Una scheda rimane sempre accessibile")
        settings.setTab(.timer, visible: false)
        precondition(settings.visibleTabs == [.timer])
        settings.setTab(.notes, visible: true)
        settings.moveTab(.notes, offset: -1)
        settings.defaultTabIndex = ExpandedTab.notes.rawValue
        settings.setTab(.notes, visible: false)
        precondition(settings.lastTab == .timer && settings.defaultTabIndex == -1)
        settings.setTab(.notes, visible: true)
        let state = NotchState(settings: settings)
        state.expand(tab: .timer)
        state.switchToAdjacentTab(direction: .right)
        precondition(state.displayState == .expanded(tab: .notes))
        state.switchToAdjacentTab(direction: .right)
        precondition(state.displayState == .expanded(tab: .timer))
        state.switchToAdjacentTab(direction: .left)
        precondition(state.displayState == .expanded(tab: .notes))
        state.collapse()
        state.switchToAdjacentTab(direction: .left)
        precondition(!state.displayState.isExpanded)
        let restored = ModuleSettings(defaults: defaults, usesSystemServices: false)
        precondition(restored.visibleTabs == settings.visibleTabs)
        settings.compactContent = 2
        settings.reduceAnimations = true
        settings.accentColorIndex = 3
        let personalized = ModuleSettings(defaults: defaults, usesSystemServices: false)
        precondition(personalized.compactContent == 2 && personalized.reduceAnimations)
        precondition(personalized.accentColorIndex == 3)
        precondition(personalized.showsCompactActivity(musicPlaying: true))
        settings.compactContent = 1
        precondition(!settings.showsCompactActivity(musicPlaying: true))
        precondition(settings.showsCompactActivity(musicPlaying: false))
        settings.compactSideViewsEnabled = false
        precondition(settings.showsCompactProgress && !settings.showsCompactMusic,
                     "Nascondere le viste laterali non nasconde l’avanzamento")
        precondition(!settings.showsCompactActivity(musicPlaying: true),
                     "La priorità della musica non dipende dalle viste laterali")
        settings.compactSideViewsEnabled = true
        settings.compactContent = 3
        precondition(!settings.showsCompactProgress)
        precondition(!settings.showsCompactMusic && !settings.showsCompactActivity(musicPlaying: false))
        let tabsBeforeReset = settings.visibleTabs
        settings.resetAppearance()
        precondition(settings.visibleTabs == tabsBeforeReset)
        precondition(settings.compactContent == 3 && settings.reduceAnimations)
        settings.customAccentRGB = [0.12, 0.34, 0.56]
        precondition(ModuleSettings(defaults: defaults, usesSystemServices: false).customAccentRGB == [0.12, 0.34, 0.56])
        defaults.set([2.0, -1.0, 0.5], forKey: "mod.customAccentRGB")
        precondition(ModuleSettings(defaults: defaults, usesSystemServices: false).customAccentRGB.isEmpty)
        defaults.set(999, forKey: "mod.compactContent")
        precondition(ModuleSettings(defaults: defaults, usesSystemServices: false).compactContent == 0)

    }

    static func checkPomodoro() {
        var session = PomodoroSession()
        for round in 1...4 {
            precondition(session.phase == .focus && session.minutes == 25)
            session.advance()
            precondition(session.completedFocusSessions == round)
            precondition(session.minutes == (round == 4 ? 15 : 5))
            session.advance()
            precondition(session.phase == .focus && session.completedFocusSessions == round)
        }
    }

    static func checkFiles() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("DynamicIsland-file-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let source = temp.appendingPathComponent("originale.txt")
        try Data("Contenuto intatto".utf8).write(to: source)
        let occupied = temp.appendingPathComponent("esistente.txt")
        try Data("Non toccare".utf8).write(to: occupied)
        do { _ = try ShelfFileActions.rename(source, to: occupied.lastPathComponent); preconditionFailure("Deve rifiutare collisioni") }
        catch { let contents = try String(contentsOf: occupied, encoding: .utf8); precondition(contents == "Non toccare") }
        do { _ = try ShelfFileActions.rename(source, to: "../fuori"); preconditionFailure("Deve rifiutare traversal") } catch {}
        do { _ = try ShelfFileActions.rename(source, to: "esistente"); preconditionFailure("Controlla collisioni dopo aggiunta estensione") } catch {}
        let automatic = try ShelfFileActions.rename(source, to: "nuovo nome")
        precondition(automatic.lastPathComponent == "nuovo nome.txt")
        let trailingDot = try ShelfFileActions.rename(automatic, to: "altro nome.")
        precondition(trailingDot.lastPathComponent == "altro nome.txt")
        let explicit = try ShelfFileActions.rename(trailingDot, to: "scelto.md")
        precondition(explicit.lastPathComponent == "scelto.md")
        let renamed = try ShelfFileActions.rename(explicit, to: "caffè con spazi.txt")
        let directory = temp.appendingPathComponent("cartella.v1")
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        let renamedDirectory = try ShelfFileActions.rename(directory, to: "cartella nuova")
        precondition(renamedDirectory.lastPathComponent == "cartella nuova")
        let noExtension = temp.appendingPathComponent("README")
        try Data("Testo".utf8).write(to: noExtension)
        let noExtensionResult = try ShelfFileActions.rename(noExtension, to: "LEGGIMI")
        precondition(noExtensionResult.lastPathComponent == "LEGGIMI")
        precondition(fm.fileExists(atPath: renamed.path) && !fm.fileExists(atPath: source.path))
        let zip1 = try ShelfFileActions.compress(renamed, outputDirectory: temp)
        let zip2 = try ShelfFileActions.compress(renamed, outputDirectory: temp)
        precondition(zip1 != zip2 && fm.fileExists(atPath: renamed.path))
        let extraction = temp.appendingPathComponent("extracted")
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip1.path, extraction.path]
        try unzip.run(); unzip.waitUntilExit()
        precondition(unzip.terminationStatus == 0)
        let extracted = try String(contentsOf: extraction.appendingPathComponent(renamed.lastPathComponent), encoding: .utf8)
        precondition(extracted == "Contenuto intatto")
        let folder = temp.appendingPathComponent("Cartella")
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("interno".utf8).write(to: folder.appendingPathComponent("file.txt"))
        do { _ = try ShelfFileActions.compress(folder, outputDirectory: folder); preconditionFailure("Nessuno ZIP ricorsivo") } catch {}
        let folderZip = try ShelfFileActions.compress(folder, outputDirectory: temp)
        let folderUnzip = Process()
        folderUnzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        folderUnzip.arguments = ["-x", "-k", folderZip.path, extraction.path]
        try folderUnzip.run(); folderUnzip.waitUntilExit()
        precondition(fm.fileExists(atPath: extraction.appendingPathComponent("Cartella/file.txt").path))
        let context = CGContext(data: nil, width: 800, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!
        let original = temp.appendingPathComponent("immagine.png")
        let destination = CGImageDestinationCreateWithURL(original as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        let resized = try ShelfFileActions.resize(original, maxSide: 512, outputDirectory: temp)
        let output = CGImageSourceCreateWithURL(resized as CFURL, nil)!
        let result = CGImageSourceCreateImageAtIndex(output, 0, nil)!
        precondition(result.width == 512 && result.height == 256)
        precondition(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(original as CFURL, nil)!, 0, nil)!.width == 800)
    }
}
