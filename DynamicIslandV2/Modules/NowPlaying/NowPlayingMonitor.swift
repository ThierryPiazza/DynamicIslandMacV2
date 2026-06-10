import AppKit
import Combine

struct NowPlayingInfo {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var artwork: NSImage? = nil
    var duration: Double = 0
    var elapsed: Double = 0
    var isPlaying: Bool = false
    var source: String = ""
    var sourceBundleID: String = ""
    var lastFetchDate: Date = .distantPast

    var hasContent: Bool { !title.isEmpty }
    var isActivelyPlaying: Bool { isPlaying && hasContent }

    func liveElapsed() -> Double {
        guard isPlaying else { return elapsed }

        let calculated = elapsed + Date().timeIntervalSince(lastFetchDate)
        return duration > 0 ? min(calculated, duration) : calculated
    }

    mutating func reset() {
        title = ""
        artist = ""
        album = ""
        artwork = nil
        duration = 0
        elapsed = 0
        isPlaying = false
        source = ""
        sourceBundleID = ""
        lastFetchDate = .distantPast
    }
}

private let knownBrowserBundleIDs: Set<String> = [
    "company.thebrowser.Browser",
    "com.google.Chrome",
    "com.google.Chrome.beta",
    "com.microsoft.edgemac",
    "com.brave.Browser",
    "com.apple.Safari",
    "org.mozilla.firefox",
    "com.operasoftware.Opera",
]

final class NowPlayingMonitor: ObservableObject {
    @Published var info = NowPlayingInfo()

    private let bridge = MediaRemoteBridge.shared
    private let playerObserver = NowPlayingObserver()
    private let browserObserver = BrowserObserver()
    private let artworkFetcher = ArtworkFetcher()
    private let settings = ModuleSettings.shared
    private var cancellables = Set<AnyCancellable>()

    /// Timer leggero solo per pulire lo stato a fine brano.
    /// Non aggiorna `elapsed` ogni secondo: la progress bar usa `liveElapsed()`.
    private var endTimer: Timer?

    init() {
        playerObserver.onChange = { [weak self] p in
            self?.applyPlayer(p)
        }

        browserObserver.onChange = { [weak self] track in
            self?.applyBrowser(track)
        }

        if settings.nowPlayingEnabled && settings.browserObserverEnabled {
            browserObserver.start()
        }
        observeSettings()
    }

    /// I toggle "Now Playing" e "Browser" delle impostazioni spengono davvero
    /// gli osservatori (e il polling AppleScript), non solo la UI.
    private func observeSettings() {
        settings.$nowPlayingEnabled
            .combineLatest(settings.$browserObserverEnabled)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] nowPlaying, browser in
                guard let self else { return }
                if nowPlaying && browser {
                    self.browserObserver.start()
                } else {
                    self.browserObserver.stop()
                    if !nowPlaying || knownBrowserBundleIDs.contains(self.info.sourceBundleID) {
                        self.resetNowPlaying()
                    }
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        endTimer?.invalidate()
        browserObserver.stop()
    }

    // MARK: - Native player

    private func applyPlayer(_ p: NowPlayingObserver.PlayerInfo) {
        guard settings.nowPlayingEnabled else { return }
        if !p.isPlaying && p.title.isEmpty {
            if info.sourceBundleID == p.bundleID || info.sourceBundleID.isEmpty {
                resetNowPlaying()
            }
            return
        }

        let titleChanged = p.title != info.title || p.artist != info.artist

        updateInfo(
            title: p.title,
            artist: p.artist,
            album: p.album,
            duration: p.duration,
            elapsed: p.elapsed,
            isPlaying: p.isPlaying,
            source: displayName(for: p.bundleID),
            bundleID: p.bundleID
        )

        if titleChanged {
            fetchArtwork(title: p.title, artist: p.artist)
        }
    }

    // MARK: - Browser player

    private func applyBrowser(_ track: BrowserObserver.BrowserTrack?) {
        guard settings.nowPlayingEnabled else { return }
        guard let track else {
            if knownBrowserBundleIDs.contains(info.sourceBundleID) {
                resetNowPlaying()
            }
            return
        }

        // Se un player nativo sta già suonando, non far sovrascrivere il titolo da un browser aperto.
        if !knownBrowserBundleIDs.contains(info.sourceBundleID) && info.isActivelyPlaying {
            return
        }

        let titleChanged = track.title != info.title || track.artist != info.artist

        // Se il browser dice "playing" ma la posizione non avanza tra due poll,
        // il media è in realtà fermo: non tenere l'island espansa.
        var isPlaying = track.isPlaying
        if isPlaying, !titleChanged, info.sourceBundleID == track.bundleID {
            let dt = Date().timeIntervalSince(info.lastFetchDate)
            let progressed = track.elapsed - info.elapsed
            if dt > 2, progressed < min(1, dt * 0.5) {
                isPlaying = false
            }
        }

        updateInfo(
            title: track.title,
            artist: track.artist,
            album: "",
            duration: track.duration,
            elapsed: track.elapsed,
            isPlaying: isPlaying,
            source: track.source,
            bundleID: track.bundleID
        )

        if titleChanged {
            fetchArtwork(title: track.title, artist: track.artist, pageURL: track.pageURL)
        }
    }

    private func updateInfo(
        title: String,
        artist: String,
        album: String,
        duration: Double,
        elapsed: Double,
        isPlaying: Bool,
        source: String,
        bundleID: String
    ) {
        info.title = title
        info.artist = artist
        info.album = album
        info.duration = duration
        info.elapsed = elapsed
        info.isPlaying = isPlaying
        info.source = source
        info.sourceBundleID = bundleID
        info.lastFetchDate = Date()

        scheduleEndTimerIfNeeded()
    }

    private func resetNowPlaying() {
        info.reset()
        endTimer?.invalidate()
        endTimer = nil
    }

    // MARK: - Artwork

    private func fetchArtwork(title: String, artist: String, pageURL: String = "") {
        info.artwork = nil
        guard !title.isEmpty else { return }

        artworkFetcher.fetch(title: title, artist: artist, bundleID: info.sourceBundleID, pageURL: pageURL) { [weak self] image in
            guard let self else { return }
            // Evita che una risposta vecchia aggiorni artwork di un brano nuovo.
            guard self.info.title == title, self.info.artist == artist else { return }
            self.info.artwork = image
        }
    }

    // MARK: - End timer

    private func scheduleEndTimerIfNeeded() {
        endTimer?.invalidate()
        endTimer = nil

        guard info.isActivelyPlaying, info.duration > 0 else { return }

        let remaining = max(1, info.duration - info.liveElapsed() + 1.0)
        let t = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.info.duration > 0, self.info.liveElapsed() >= self.info.duration {
                self.resetNowPlaying()
            }
        }
        t.tolerance = min(2.0, max(0.2, remaining * 0.1))
        endTimer = t
    }

    // MARK: - Helpers

    private func displayName(for bundleID: String) -> String {
        switch bundleID {
        case "com.apple.Music":
            return "Music"
        case "com.spotify.client":
            return "Spotify"
        case "com.coppertino.Vox":
            return "Vox"
        default:
            return bundleID.components(separatedBy: ".").last ?? bundleID
        }
    }

    // MARK: - Open source app

    func openSourceApp() {
        let bundleID = info.sourceBundleID

        guard !bundleID.isEmpty else { return }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }

        NSWorkspace.shared.open(appURL)
    }

    // MARK: - Controls

    /// Feedback ottimistico: l'icona cambia subito invece di aspettare 4–8s
    /// il prossimo poll. Lo stato vero arriva dalla notifica del player o dal
    /// poll del browser forzato qui sotto, e corregge se necessario.
    func togglePlayPause() {
        bridge.send(.togglePlayPause, fallbackBundleID: info.sourceBundleID)
        if info.hasContent {
            info.elapsed = info.liveElapsed()
            info.lastFetchDate = Date()
            info.isPlaying.toggle()
            scheduleEndTimerIfNeeded()
        }
        browserObserver.pollSoon()
    }

    func nextTrack() {
        bridge.send(.nextTrack, fallbackBundleID: info.sourceBundleID)
        browserObserver.pollSoon()
    }

    func prevTrack() {
        bridge.send(.prevTrack, fallbackBundleID: info.sourceBundleID)
        browserObserver.pollSoon()
    }
}
