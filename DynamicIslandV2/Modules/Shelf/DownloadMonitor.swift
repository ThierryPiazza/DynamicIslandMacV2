import Foundation
import Combine

final class DownloadMonitor: ObservableObject {
    static let shared = DownloadMonitor()
    @Published var enabled = UserDefaults.standard.object(forKey: "downloads.enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "downloads.enabled")
            if oldValue != enabled { restart() }
        }
    }
    @Published private(set) var errorMessage: String?
    private let queue = DispatchQueue(label: "dynamicisland.downloads", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var generation = UUID()

    deinit { timer?.cancel() }

    func restart() {
        timer?.cancel()
        timer = nil
        generation = UUID()
        errorMessage = nil
        guard enabled else { return }
        let token = generation
        let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var tracker = DownloadInboxTracker()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            do {
                let ready = tracker.ingest(try DownloadInboxTracker.snapshot(in: directory), at: Date())
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    if self.errorMessage != nil { self.errorMessage = nil }
                    ready.forEach { ShelfManager.shared.add(url: $0) }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    guard self.errorMessage == nil else { return }
                    self.errorMessage = "Accesso a Download non disponibile. Consenti l’accesso a Dynamic Island in Impostazioni di Sistema → Privacy e sicurezza → File e cartelle."
                }
            }
        }
        self.timer = timer
        timer.resume()
    }
}
