import AppKit
import Combine

struct ShelfItem: Identifiable, Codable {
    let id: UUID
    let bookmarkData: Data
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
        return try? URL(resolvingBookmarkData: bookmarkData,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &stale)
    }
}

final class ShelfManager: ObservableObject {
    static let shared = ShelfManager()
    @Published var items: [ShelfItem] = []

    private let maxItems = 4
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
        save()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func open(_ item: ShelfItem) {
        guard let url = item.resolvedURL() else { return }
        _ = url.startAccessingSecurityScopedResource()
        NSWorkspace.shared.open(url)
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
        items = saved
    }
}
