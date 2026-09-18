import SwiftUI
import AppKit

struct NotesView: View {
    @ObservedObject var store: NotesStore
    let notchState: NotchState
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var newCheck = ""
    @State private var remindersNoteID: UUID?
    @State private var showReminders = false
    @State private var checkDraft: CheckReminderDraft?

    var body: some View {
        let visibleNotes = store.filtered(query)
        return VStack(spacing: 5) {
            if let id = selectedID, let note = store.notes.first(where: { $0.id == id }) {
                editor(note)
            } else {
                HStack(spacing: 6) {
                    TextField("Cerca appunti…", text: $query).textFieldStyle(.plain)
                    Menu {
                        Button("Nuova nota") { selectedID = store.add() }
                        Button("Nuova checklist") { selectedID = store.add(checklist: true) }
                    } label: { Image(systemName: "plus") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 28, height: 24)
                    .fixedSize()
                    .help("Nuova nota o checklist")
                    .accessibilityLabel("Nuova nota o checklist")
                    Button("Fine") { notchState.collapse() }.buttonStyle(PillButtonStyle())
                }
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(visibleNotes) { note in
                            Button { selectedID = note.id } label: {
                                HStack {
                                    Image(systemName: note.pinned ? "pin.fill" : (note.isChecklist ? "checklist" : "note.text"))
                                    Text(note.displayTitle).lineLimit(1)
                                    Spacer()
                                    if note.remindersLink != nil {
                                        Image(systemName: "checklist.checked").foregroundStyle(.blue)
                                            .help("Collegata a Promemoria")
                                    }
                                    if note.isChecklist { Text("\(note.checks.filter(\.done).count)/\(note.checks.count)").foregroundStyle(.secondary) }
                                }
                                .padding(5).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain)
                            .contextMenu {
                                Button(note.pinned ? "Non fissare" : "Fissa in alto") { store.update(note.id) { $0.pinned.toggle() } }
                                if note.isChecklist {
                                    Button("Collega a Promemoria…") { openReminders(note.id) }
                                }
                                Button("Elimina nota", role: .destructive) { store.remove(note.id) }
                            }
                        }
                        if visibleNotes.isEmpty {
                            Text(query.isEmpty ? "Crea una nota con +" : "Nessun risultato").foregroundStyle(.secondary).padding(6)
                        }
                    }
                }
                if store.deletedNote != nil {
                    Button("Annulla eliminazione") { store.undoDelete() }.buttonStyle(.plain)
                }
            }
        }
        .font(.system(size: 11)).foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.top, 5)
        .alert("Appunti", isPresented: Binding(get: { store.storageMessage != nil }, set: { if !$0 { store.storageMessage = nil } })) {
            Button("OK") { store.storageMessage = nil }
        } message: { Text(store.storageMessage ?? "") }
        .onExitCommand { notchState.collapse() }
        .onAppear { notchState.isEditingNotes = true; store.refreshReminders() }
        .onDisappear { notchState.isEditingNotes = false }
        .popover(isPresented: $showReminders) { remindersPopover }
        .popover(item: $checkDraft) { draft in
            CheckReminderEditor(draft: draft,
                                isConnected: store.notes.first(where: { $0.id == draft.noteID })?.remindersLink != nil) { text, timing in
                store.update(draft.noteID) { note in
                    if draft.isNew {
                        note.checks.append(.init(text: text, timing: timing))
                    } else if let index = note.checks.firstIndex(where: { $0.id == draft.check.id }) {
                        note.checks[index].text = text
                        note.checks[index].timing = timing
                    }
                }
                if draft.isNew { newCheck = "" }
                checkDraft = nil
            } onCancel: { checkDraft = nil }
        }
    }

    private func editor(_ note: NoteEntry) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Button { selectedID = nil; newCheck = "" } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).help("Tutti gli appunti").accessibilityLabel("Tutti gli appunti")
                TextField("Titolo", text: Binding(get: { note.title }, set: { value in store.update(note.id) { $0.title = value } }))
                    .textFieldStyle(.plain)
                if note.isChecklist {
                    Button { openReminders(note.id) } label: {
                        Image(systemName: "checklist.checked")
                            .foregroundStyle(note.remindersLink == nil ? Color.secondary : .blue)
                    }.buttonStyle(.plain).help("Collega a Promemoria e ai widget iPhone")
                        .accessibilityLabel("Collegamento a Promemoria")
                }
                Button { store.update(note.id) { $0.pinned.toggle() } } label: {
                    Image(systemName: note.pinned ? "pin.fill" : "pin")
                }.buttonStyle(.plain).help("Fissa nota")
                Button("Fine") { notchState.collapse() }.buttonStyle(PillButtonStyle())
            }
            if note.isChecklist {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(note.checks) { check in
                            HStack(spacing: 5) {
                                Button { store.update(note.id) { entry in
                                    if let i = entry.checks.firstIndex(where: { $0.id == check.id }) { entry.checks[i].done.toggle() }
                                } } label: { Image(systemName: check.done ? "checkmark.circle.fill" : "circle") }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(check.done ? "Segna da completare" : "Completa voce")
                                TextField("Voce", text: Binding(get: { check.text }, set: { value in
                                    store.update(note.id) { entry in
                                        if let i = entry.checks.firstIndex(where: { $0.id == check.id }) { entry.checks[i].text = value }
                                    }
                                })).textFieldStyle(.plain).strikethrough(check.done)
                                Button { checkDraft = .init(noteID: note.id, check: check, isNew: false) } label: {
                                    Image(systemName: check.timing?.notificationDate == nil ? "calendar" : "bell.badge")
                                        .foregroundStyle(check.timing == nil ? Color.secondary : .blue)
                                }.buttonStyle(.plain)
                                    .help(check.timing?.date.map { "Scadenza: " + $0.formatted(date: .abbreviated, time: check.timing?.hasTime == true ? .shortened : .omitted) } ?? "Scadenza e notifica")
                                    .accessibilityLabel("Modifica scadenza e notifica")
                                Button { store.update(note.id) { $0.checks.removeAll { $0.id == check.id } } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.plain).help("Rimuovi voce")
                            }
                        }
                    }
                }
                HStack {
                    TextField("Aggiungi voce…", text: $newCheck).textFieldStyle(.plain).onSubmit { addCheck(note.id) }
                    Button { addCheck(note.id) } label: { Image(systemName: "plus.circle") }.buttonStyle(.plain)
                        .help("Aggiungi promemoria").accessibilityLabel("Aggiungi promemoria")
                        .disabled(newCheck.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                NotesEditor(text: Binding(get: { note.body }, set: { value in store.update(note.id) { $0.body = value } }),
                            onFocus: { _ in }, onClose: { notchState.collapse() })
                    .id(note.id)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func addCheck(_ id: UUID) {
        let text = newCheck.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        checkDraft = .init(noteID: id, check: .init(text: text), isNew: true)
    }

    private func openReminders(_ id: UUID) {
        remindersNoteID = id
        showReminders = true
        store.prepareReminders()
    }

    private var remindersPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Promemoria su iPhone").font(.headline)
            if let note = store.notes.first(where: { $0.id == remindersNoteID }) {
                if let link = note.remindersLink {
                    Label(link.calendarTitle, systemImage: "checklist.checked")
                    Text("Voci, testo e spunte si sincronizzano nei due sensi. Rimuovere una voce la elimina anche dalla lista collegata.")
                    HStack {
                        Button("Aggiorna") { store.refreshReminders() }.disabled(store.remindersBusy)
                        Button("Apri Promemoria") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app"))
                        }
                    }
                    Text("Su iPhone attiva Promemoria in iCloud con lo stesso Apple Account. Aggiungi il widget Promemoria nella Home e nella schermata di blocco, poi scegli questa lista. Il widget di blocco mostra poche voci.")
                    Button("Scollega (conserva entrambe le copie)") { store.disconnectReminders(note.id) }
                        .disabled(store.remindersBusy)
                } else {
                    Text("Crea una lista «Island – \(note.displayTitle)» nell’account scelto. Seleziona iCloud per vederla sull’iPhone.")
                    ForEach(store.remindersAccounts) { account in
                        Button {
                            store.connectReminders(note.id, account: account)
                        } label: {
                            Label(account.title + (account.isLocal ? " — solo questo Mac" : ""), systemImage: account.isLocal ? "desktopcomputer" : "icloud")
                        }.disabled(store.remindersBusy)
                    }
                    if store.remindersAccounts.isEmpty && !store.remindersBusy {
                        Button("Riprova accesso") { store.prepareReminders() }
                    }
                }
            }
            if store.remindersBusy { ProgressView().controlSize(.small) }
            if !store.remindersMessage.isEmpty {
                Text(store.remindersMessage).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Eliminare l’intera nota dall’Island conserva la lista in Promemoria. Gli aggiornamenti iCloud possono richiedere qualche istante.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Chiudi") { showReminders = false } }
        }
        .font(.system(size: 12))
        .padding(16).frame(width: 350)
    }
}

/// NSTextView mantiene selezione, undo e composizione del testo tra gli aggiornamenti SwiftUI.
private struct NotesEditor: NSViewRepresentable {
    @Binding var text: String
    let onFocus: (Bool) -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay

        let editor = ScratchpadTextView(frame: .zero)
        editor.isRichText = false
        editor.isEditable = true
        editor.isSelectable = true
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.textColor = .white
        editor.insertionPointColor = .white
        editor.font = .systemFont(ofSize: 12)
        editor.textContainerInset = NSSize(width: 6, height: 7)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.setAccessibilityLabel("Blocco note")
        editor.string = text
        editor.delegate = context.coordinator
        editor.onFocus = onFocus
        editor.onClose = onClose
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? ScratchpadTextView else { return }
        editor.onFocus = onFocus
        editor.onClose = onClose
        // Non riassegnare string durante la digitazione: perderebbe cursore e undo.
        if editor.string != text { editor.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesEditor
        init(_ parent: NotesEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

private final class ScratchpadTextView: NSTextView {
    var onFocus: ((Bool) -> Void)?
    var onClose: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        // Il panel è nonactivating: richiedi esplicitamente il focus per digitare.
        window?.makeKey()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocus?(false) }
        return accepted
    }

    override func cancelOperation(_ sender: Any?) { onClose?() }

    // Un’app accessory non dispone necessariamente di un menu Modifica.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard modifiers == .command || modifiers == [.command, .shift] else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a" where modifiers == .command: selectAll(nil)
        case "c" where modifiers == .command: copy(nil)
        case "v" where modifiers == .command: pasteAsPlainText(nil)
        case "x" where modifiers == .command: cut(nil)
        case "z":
            if modifiers.contains(.shift) { undoManager?.redo() }
            else { undoManager?.undo() }
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
