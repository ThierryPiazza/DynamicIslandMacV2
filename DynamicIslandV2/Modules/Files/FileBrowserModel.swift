import AppKit
import Combine

struct BrowserFile: Identifiable, Sendable {
  let url: URL
  let isDirectory: Bool
  var id: URL { url }
  var name: String { url.lastPathComponent }
}

@MainActor
final class FileBrowserModel: ObservableObject {
  static let shared = FileBrowserModel()
  @Published private(set) var directory: URL?
  @Published private(set) var favorites: [URL] = []
  @Published private(set) var files: [BrowserFile] = []
  @Published var query = "" { didSet { scheduleReload() } }
  @Published var showHidden = false { didSet { scheduleReload() } }
  @Published var searchSubfolders = false { didSet { scheduleReload() } }
  @Published var selected: URL?
  @Published private(set) var loading = false
  @Published private(set) var message: String?
  @Published private(set) var back: [URL] = []
  @Published private(set) var forward: [URL] = []
  @Published private(set) var choosingFolder = false
  private var openPanel: NSOpenPanel?
  private var reloadScheduled = false
  private var accesses: [URL] = []
  private var bookmarks: [URL: Data] = [:]
  private var favoritesRestored = false
  private var session: UUID?
  private var task: Task<Void, Never>?
  private var request = UUID()
  private var cache: [String: (date: Date, files: [BrowserFile])] = [:]
  private var metadata: NSMetadataQuery?
  private var metadataObservers: [NSObjectProtocol] = []
  private var active = false
  private let key = "files.favoriteBookmarks"

  init() {
    directory = FileManager.default.homeDirectoryForCurrentUser
  }

  func chooseFolder() {
    guard openPanel == nil else { return }
    choosingFolder = true
    let panel = NSOpenPanel()
    openPanel = panel
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Aggiungi cartella"
    panel.message = "Scegli una cartella da esplorare nell’Island."
    panel.directoryURL = directory
    panel.level = .modalPanel
    NSApp.activate(ignoringOtherApps: true)
    panel.begin { [weak self] response in
      Task { @MainActor in
        guard let self else { return }
        defer {
          self.openPanel = nil
          self.choosingFolder = false
        }
        guard response == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        do {
          let data = try await Task.detached(priority: .utility) {
            try url.bookmarkData(
              options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
          }.value
          self.bookmarks[url] = data
          if !self.favorites.contains(url) {
            if access { self.accesses.append(url) }
            self.favorites.append(url)
            self.saveFavorites()
          } else if access {
            url.stopAccessingSecurityScopedResource()
          }
          self.navigate(url)
        } catch {
          if access { url.stopAccessingSecurityScopedResource() }
          self.message = "Impossibile conservare l’accesso: \(error.localizedDescription)"
        }
      }
    }
  }

  private func scheduleReload() {
    guard !reloadScheduled else { return }
    reloadScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.reloadScheduled = false
      self.reload()
    }
  }

  func removeFavorite(_ url: URL) {
    favorites.removeAll { $0 == url }
    saveFavorites()
    // Keep access alive for any current preview or drag until the app exits.
  }

  private func saveFavorites() {
    UserDefaults.standard.set(favorites.compactMap { bookmarks[$0] }, forKey: key)
  }

  private func restoreFavorites() {
    guard !favoritesRestored else { return }
    favoritesRestored = true
    let saved = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
    Task { [weak self] in
      let restored = await Task.detached(priority: .utility) {
        saved.compactMap { data -> (URL, Data)? in
          var stale = false
          guard
            let url = try? URL(
              resolvingBookmarkData: data,
              options: [.withSecurityScope, .withoutUI, .withoutMounting],
              bookmarkDataIsStale: &stale)
          else { return nil }
          return (url, data)
        }
      }.value
      guard let self else { return }
      for (url, data) in restored where !self.favorites.contains(url) {
        if url.startAccessingSecurityScopedResource() { self.accesses.append(url) }
        self.bookmarks[url] = data
        self.favorites.append(url)
      }
    }
  }

  func navigate(_ url: URL, record: Bool = true) {
    let url = url.standardizedFileURL
    if record, let directory, directory != url {
      back.append(directory)
      if back.count > 100 { back.removeFirst() }
      forward = []
    }
    directory = url
    files = []
    selected = nil
    if query.isEmpty { reload() } else { query = "" }
  }

  func goBack() {
    guard let target = back.popLast() else { return }
    if let directory { forward.append(directory) }
    navigate(target, record: false)
  }
  func goForward() {
    guard let target = forward.popLast() else { return }
    if let directory { back.append(directory) }
    navigate(target, record: false)
  }

  var canGoUp: Bool {
    guard let directory else { return false }
    return directory.standardizedFileURL.path != "/"
  }

  var locations: [(name: String, url: URL)] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return [
      ("Cartella utente", home),
      ("Scrivania", home.appendingPathComponent("Desktop")),
      ("Documenti", home.appendingPathComponent("Documents")),
      ("Download", home.appendingPathComponent("Downloads")),
      ("Applicazioni", URL(fileURLWithPath: "/Applications")),
      ("Disco del Mac", URL(fileURLWithPath: "/")),
      ("Dischi e volumi", URL(fileURLWithPath: "/Volumes")),
    ]
  }

  func goToPath(_ path: String) {
    let expanded = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString)
      .expandingTildeInPath
    guard expanded.hasPrefix("/") else {
      message = "Inserisci un percorso assoluto o che inizia con ~."
      return
    }
    navigate(URL(fileURLWithPath: expanded, isDirectory: true))
  }

  func open(_ file: BrowserFile) {
    if file.isDirectory {
      navigate(file.url)
    } else if !NSWorkspace.shared.open(file.url) {
      message = "Impossibile aprire questo file."
    }
  }

  func activate(session: UUID) {
    self.session = session
    active = true
    restoreFavorites()
    // Reload uses the short-lived cache; reopening never starts a recursive disk scan.
    reload()
  }

  func deactivate(session: UUID) {
    guard self.session == session else { return }
    self.session = nil
    active = false
    task?.cancel()
    request = UUID()
    stopMetadata()
    loading = false
  }

  private func stopMetadata() {
    metadata?.stop()
    metadata = nil
    metadataObservers.forEach { NotificationCenter.default.removeObserver($0) }
    metadataObservers = []
  }

  func reload(force: Bool = false) {
    guard active else { return }
    task?.cancel()
    stopMetadata()
    let token = UUID()
    request = token
    guard let directory else { return }
    let includeHidden = showHidden
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let recursive = searchSubfolders && !term.isEmpty
    let cacheKey = directory.path + (includeHidden ? "|all" : "|visible")
    message = nil
    if !recursive, !force, let cached = cache[cacheKey], Date().timeIntervalSince(cached.date) < 15
    {
      apply(cached.files, term: term)
      loading = false
      return
    }
    loading = true
    task = Task { [weak self] in
      if !term.isEmpty {
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      }
      guard !Task.isCancelled, let self, self.request == token else { return }
      if recursive {
        self.startMetadata(
          directory: directory, term: term, includeHidden: includeHidden, token: token)
        do { try await Task.sleep(for: .seconds(8)) } catch { return }
        if self.request == token && self.loading {
          self.loading = false
          self.message = "Spotlight sta ancora cercando. Puoi cambiare cartella o ricerca."
        }
        return
      }
      let worker = Task.detached(priority: .userInitiated) { () -> Result<[BrowserFile], Error> in
        Result {
          let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]
          let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: includeHidden ? [] : [.skipsHiddenFiles])
          var result: [BrowserFile] = []
          for url in urls {
            try Task.checkCancellation()
            let values = try? url.resourceValues(forKeys: keys)
            result.append(
              BrowserFile(
                url: url,
                isDirectory: values?.isDirectory == true && values?.isPackage != true))
          }
          return result.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
          }
        }
      }
      let result = await withTaskCancellationHandler {
        await worker.value
      } onCancel: {
        worker.cancel()
      }
      guard !Task.isCancelled, self.active, self.request == token else { return }
      switch result {
      case .success(let entries):
        if self.cache.count >= 12,
          let oldest = self.cache.min(by: { $0.value.date < $1.value.date })?.key
        {
          self.cache.removeValue(forKey: oldest)
        }
        self.cache[cacheKey] = (Date(), entries)
        self.apply(entries, term: term)
      case .failure(let error):
        self.files = []
        self.message = "Cartella non accessibile: \(error.localizedDescription)"
      }
      self.loading = false
    }
  }

  private func apply(_ entries: [BrowserFile], term: String) {
    files = term.isEmpty ? entries : entries.filter { $0.name.localizedStandardContains(term) }
    if !files.contains(where: { $0.url == selected }) { selected = nil }
  }

  private func startMetadata(directory: URL, term: String, includeHidden: Bool, token: UUID) {
    let query = NSMetadataQuery()
    query.searchScopes = [directory.path]
    query.predicate = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, term)
    query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)]
    metadata = query
    for name in [
      NSNotification.Name.NSMetadataQueryDidFinishGathering, NSNotification.Name.NSMetadataQueryDidUpdate,
    ] {
      metadataObservers.append(
        NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) {
          [weak self] _ in
          Task { @MainActor [weak self] in
            guard let self, self.request == token, self.active else { return }
            self.receiveMetadata(includeHidden: includeHidden)
          }
        })
    }
    if !query.start() {
      stopMetadata()
      loading = false
      message = "Ricerca indicizzata non disponibile. Usa la ricerca nella cartella."
    }
  }

  private func receiveMetadata(includeHidden: Bool) {
    guard let metadata else { return }
    metadata.disableUpdates()
    defer { metadata.enableUpdates() }
    var result: [BrowserFile] = []
    var seen = Set<URL>()
    for index in 0..<metadata.resultCount {
      guard let item = metadata.result(at: index) as? NSMetadataItem,
        let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
      else { continue }
      let url = URL(fileURLWithPath: path)
      if !includeHidden && url.pathComponents.contains(where: { $0.hasPrefix(".") }) { continue }
      guard seen.insert(url).inserted else { continue }
      let types = item.value(forAttribute: NSMetadataItemContentTypeTreeKey) as? [String] ?? []
      result.append(
        BrowserFile(
          url: url,
          isDirectory: types.contains("public.folder") && !types.contains("com.apple.package")))
      if result.count == 500 { break }
    }
    files = result
    if !files.contains(where: { $0.url == selected }) { selected = nil }
    loading = false
    message =
      metadata.resultCount >= 500
      ? "Mostrati fino a 500 risultati indicizzati. Restringi la ricerca."
      : "Ricerca Spotlight: le posizioni non indicizzate non sono incluse."
  }
}
