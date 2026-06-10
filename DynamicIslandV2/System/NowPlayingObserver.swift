import AppKit

/// Legge lo stato Now Playing ascoltando le DistributedNotification
/// che ogni player trasmette — nessun entitlement richiesto.
final class NowPlayingObserver {

    var onChange: ((PlayerInfo) -> Void)?

    struct PlayerInfo {
        var title: String
        var artist: String
        var album: String
        var isPlaying: Bool
        var duration: Double    // secondi, 0 se non disponibile
        var elapsed: Double
        var bundleID: String    // app sorgente
    }

    private var observers: [NSObjectProtocol] = []

    init() { subscribe() }
    deinit { observers.forEach { DistributedNotificationCenter.default().removeObserver($0) } }

    // MARK: - Subscriptions

    private func subscribe() {
        let nc = DistributedNotificationCenter.default()

        // Music.app (macOS)
        add(nc, name: "com.apple.Music.playerInfo") { [weak self] n in
            self?.handleAppleMusic(n)
        }
        // iTunes legacy / Music su versioni vecchie
        add(nc, name: "com.apple.iTunes.playerInfo") { [weak self] n in
            self?.handleAppleMusic(n)
        }
        // Spotify
        add(nc, name: "com.spotify.client.PlaybackStateChanged") { [weak self] n in
            self?.handleSpotify(n)
        }
        // Vox
        add(nc, name: "com.coppertino.Vox.trackChanged") { [weak self] n in
            self?.handleVox(n)
        }
        // Doppler
        add(nc, name: "com.brushedtype.doppler.track-changed") { [weak self] n in
            self?.handleGeneric(n, playing: true)
        }
    }

    private func add(_ nc: DistributedNotificationCenter, name: String, block: @escaping (Notification) -> Void) {
        let obs = nc.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main, using: block)
        observers.append(obs)
    }

    // MARK: - Parsers

    private func handleAppleMusic(_ n: Notification) {
        let d = n.userInfo ?? [:]
        let state = d["Player State"] as? String ?? ""
        let isPlaying = state == "Playing"

        // Duration in Music è in secondi (Double) o ms a seconda della versione
        var duration = d["Total Time"] as? Double ?? 0
        if duration > 10_000 { duration /= 1000 }  // converti da ms a secondi se necessario

        let elapsed = d["Player Position"] as? Double ?? 0

        emit(PlayerInfo(
            title: d["Name"]   as? String ?? "",
            artist: d["Artist"] as? String ?? "",
            album: d["Album"]  as? String ?? "",
            isPlaying: isPlaying,
            duration: duration,
            elapsed: elapsed,
            bundleID: "com.apple.Music"
        ))
    }

    private func handleSpotify(_ n: Notification) {
        let d = n.userInfo ?? [:]
        let state = d["Player State"] as? String ?? ""

        // Spotify invia "Duration" in millisecondi e la posizione in "Playback Position" (secondi)
        var duration = d["Duration"] as? Double ?? 0
        if duration > 10_000 { duration /= 1000 }

        emit(PlayerInfo(
            title: d["Name"]   as? String ?? d["Track"] as? String ?? "",
            artist: d["Artist"] as? String ?? "",
            album: d["Album"]  as? String ?? "",
            isPlaying: state == "Playing",
            duration: duration,
            elapsed: d["Playback Position"] as? Double ?? 0,
            bundleID: "com.spotify.client"
        ))
    }

    private func handleVox(_ n: Notification) {
        let d = n.userInfo ?? [:]
        emit(PlayerInfo(
            title: d["title"]  as? String ?? "",
            artist: d["artist"] as? String ?? "",
            album: d["album"]  as? String ?? "",
            isPlaying: true,
            duration: d["length"] as? Double ?? 0,
            elapsed: 0,
            bundleID: "com.coppertino.Vox"
        ))
    }

    private func handleGeneric(_ n: Notification, playing: Bool) {
        let d = n.userInfo ?? [:]
        emit(PlayerInfo(
            title: d["title"]  as? String ?? d["name"] as? String ?? "",
            artist: d["artist"] as? String ?? "",
            album: d["album"]  as? String ?? "",
            isPlaying: playing,
            duration: d["duration"] as? Double ?? 0,
            elapsed: 0,
            bundleID: n.name.rawValue
        ))
    }

    private func emit(_ info: PlayerInfo) {
        DispatchQueue.main.async { self.onChange?(info) }
    }
}
