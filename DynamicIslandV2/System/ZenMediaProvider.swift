import Foundation

/// Native Messaging host writes atomic snapshots; reading never depends on Zen's
/// foreground state. Expiration covers crashes, discarded tabs and lost ports.
@MainActor
final class ZenMediaProvider {
    var onChange: ((ZenMediaSnapshot.Track?) -> Void)?
    private var timer: Timer?
    private var lastData: Data?
    private var hadTrack = false
    private let file: URL

    init(directory: URL = ZenMediaSnapshot.directory) {
        file = directory.appendingPathComponent("snapshot.json")
    }
    deinit { timer?.invalidate() }
    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
    }
    func stop() {
        timer?.invalidate()
        timer = nil
        lastData = nil
        hadTrack = false
        onChange?(nil)
    }
    func poll(at now: Date = Date()) {
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let data = size > 0 && size <= 768_000 ? try? Data(contentsOf: file) : nil
        let track = data.flatMap { try? JSONDecoder().decode(ZenMediaSnapshot.self, from: $0) }?.freshTrack(at: now)
        guard data != lastData || (track == nil && hadTrack) else { return }
        lastData = data
        hadTrack = track != nil
        onChange?(track)
    }
}
