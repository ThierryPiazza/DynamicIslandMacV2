import AppKit
import Combine

struct ShelfItem: Identifiable, Codable {
    let id: UUID
    var bookmarkData: Data
    var displayName: String
    var path: String

    init(url: URL) throws {
        id = UUID()
        bookmarkData = try url.bookmarkData(options: .withSecurityScope,
                                             includingResourceValuesForKeys: nil,
                                             relativeTo: nil)
        displayName = url.lastPathComponent
        path = url.path
    }

    func resolvedURL() -> URL? {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: bookmarkData,
                              options: [.withSecurityScope, .withoutUI, .withoutMounting],
                              relativeTo: nil, bookmarkDataIsStale: &stale) { return url }
        let fallback = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }
}

final class ShelfManager: ObservableObject {
    static let shared = ShelfManager()
    @Published var items: [ShelfItem] = []
    @Published private(set) var additionCount = 0
    @Published private(set) var busyIDs = Set<UUID>()
    var isHoveringActionFiles = false
    @Published var showsActions = false
    @Published var actionMessage: String?
    @Published var renameItem: ShelfItem?
    @Published var renameText = ""
    private let actionQueue = DispatchQueue(label: "dynamicisland.shelf.actions", qos: .userInitiated)

    @Published var moveItem: ShelfItem?
    @Published private(set) var lastMove: (item: ShelfItem, original: URL)?
    @Published private(set) var moveNotice: String?

    private let maxItems = 50
    private let saveKey  = "shelf.items.v2"
    private var cancellables = Set<AnyCancellable>()

    private init() {
        load()
        // Quando l'utente disattiva la persistenza, rimuovi subito i dati salvati;
        // quando la riattiva, salva lo stato corrente.
        ModuleSettings.shared.$shelfPersistenceEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.save()
                } else {
                    UserDefaults.standard.removeObject(forKey: self.saveKey)
                }
            }
            .store(in: &cancellables)
    }

    func add(url: URL) {
        guard (try? url.checkResourceIsReachable()) == true else { return }
        if items.contains(where: { $0.path == url.path }) { return }
        guard let item = try? ShelfItem(url: url) else { return }
        // FIFO: inserisci in testa, rimuovi la coda se supera il max
        items.insert(item, at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
        additionCount += 1
        save()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func open(_ item: ShelfItem) {
        guard let url = item.resolvedURL() else {
            actionMessage = "File non disponibile. Potrebbe essere stato spostato o eliminato."
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        NSWorkspace.shared.open(url)
        if access { url.stopAccessingSecurityScopedResource() }
    }

    func copyPath(_ item: ShelfItem) {
        let url = item.resolvedURL() ?? URL(fileURLWithPath: item.path)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    func beginRename(_ item: ShelfItem) {
        renameText = item.resolvedURL()?.lastPathComponent ?? item.displayName
        renameItem = item
    }

    func rename(_ item: ShelfItem, name: String) {
        perform(item, updateExisting: true) { try ShelfFileActions.rename($0, to: name) }
    }

    func compress(_ item: ShelfItem) {
        let output = ModuleSettings.shared.outputDirectory
        perform(item) { try ShelfFileActions.compress($0, outputDirectory: output) }
    }

    func resize(_ item: ShelfItem, maxSide: Int) {
        let output = ModuleSettings.shared.outputDirectory
        let replace = ModuleSettings.shared.replaceEditedOriginal
        perform(item, updateExisting: replace) { source in
            let result = try ShelfFileActions.resize(source, maxSide: maxSide, outputDirectory: output)
            return try FileEditResult.finish(result, source: source, replace: replace)
        }
    }

    func convert(_ item: ShelfItem, option: ConversionOption) {
        guard !busyIDs.contains(item.id) else { return }
        guard let source = item.resolvedURL() else {
            actionMessage = "File non disponibile. Aggiungilo di nuovo alla Shelf."
            return
        }
        let updateExisting = ModuleSettings.shared.replaceEditedOriginal && option.ext != "txt"
        busyIDs.insert(item.id)
        Task { @MainActor in
            let result: Result<URL, Error>
            do {
                result = .success(try await FileConverter().convert(url: source, toExt: option.ext))
            } catch {
                result = .failure(error)
            }
            completeAction(item, updateExisting: updateExisting, result: result)
        }
    }

    func move(_ item: ShelfItem, into directory: URL, undo: Bool = false) {
        guard !busyIDs.contains(item.id) else { return }
        guard let source = item.resolvedURL() else {
            actionMessage = "File non disponibile. Aggiungilo di nuovo alla Shelf."
            return
        }
        busyIDs.insert(item.id)
        actionQueue.async { [weak self] in
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            let result = Result { try DocumentFileOperations.move(source, into: directory) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busyIDs.remove(item.id)
                switch result {
                case .success(let destination):
                    var updated = item
                    updated.path = destination.path
                    updated.displayName = destination.lastPathComponent
                    updated.bookmarkData = (try? ShelfItem(url: destination))?.bookmarkData ?? Data()
                    self.items.removeAll { $0.id == item.id || $0.path == destination.path }
                    if undo {
                        self.items.insert(updated, at: 0)
                        if self.items.count > self.maxItems { self.items = Array(self.items.prefix(self.maxItems)) }
                    }
                    self.lastMove = undo ? nil : (updated, source)
                    self.moveNotice = undo ? "Spostamento annullato" : "Spostato in " + directory.lastPathComponent
                    self.moveItem = nil
                    self.save()
                case .failure(let error):
                    self.actionMessage = (error as? CocoaError)?.code == .fileWriteFileExists
                        ? "Esiste già un file con questo nome. Rinomina il file o scegli un’altra cartella. Nessun file è stato sovrascritto."
                        : error.localizedDescription
                }
            }
        }
    }

    func undoMove() {
        guard let lastMove else { return }
        move(lastMove.item, into: lastMove.original.deletingLastPathComponent(), undo: true)
    }

    private func perform(_ item: ShelfItem, updateExisting: Bool = false, action: @escaping (URL) throws -> URL) {
        guard !busyIDs.contains(item.id) else { return }
        guard let url = item.resolvedURL() else { actionMessage = "File non disponibile. Aggiungilo di nuovo alla Shelf."; return }
        busyIDs.insert(item.id)
        actionQueue.async { [weak self] in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let result = Result { try action(url) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.completeAction(item, updateExisting: updateExisting, result: result)
            }
        }
    }

    private func completeAction(_ item: ShelfItem, updateExisting: Bool, result: Result<URL, Error>) {
        busyIDs.remove(item.id)
        switch result {
        case .success(let destination):
            if updateExisting, let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].displayName = destination.lastPathComponent
                items[index].path = destination.path
                if let replacement = try? ShelfItem(url: destination) {
                    items[index].bookmarkData = replacement.bookmarkData
                }
                save()
            } else if !updateExisting { add(url: destination) }
            actionMessage = "Salvato: " + destination.lastPathComponent
        case .failure(let error): actionMessage = error.localizedDescription
        }
    }

    private func save() {
        guard ModuleSettings.shared.shelfPersistenceEnabled else { return }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func load() {
        guard ModuleSettings.shared.shelfPersistenceEnabled else { return }
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let saved = try? JSONDecoder().decode([ShelfItem].self, from: data)
        else { return }
        items = Array(saved.prefix(maxItems))
    }
}
