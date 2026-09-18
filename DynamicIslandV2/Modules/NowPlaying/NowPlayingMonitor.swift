import AppKit
import Combine
import MediaRemoteAdapter

struct NowPlayingInfo {
    var title = ""
    var artist = ""
    var album = ""
    var artwork: NSImage?
    var duration: Double = 0
    var elapsed: Double = 0
    var playbackRate: Double = 1
    var isPlaying = false
    var source = ""
    var sourceBundleID = ""
    var sourceIdentity = ""
    var pageURL = ""
    var artworkURL = ""
    var canToggle = false
    var canSkip = false
    var lastFetchDate = Date.distantPast

    var hasContent: Bool { !title.isEmpty }
    var isActivelyPlaying: Bool { isPlaying && hasContent }
    var contentIdentity: String { "\(sourceIdentity)|\(title)|\(artist)|\(album)" }

    func liveElapsed(at now: Date = Date()) -> Double {
        let delta = isPlaying ? max(0, now.timeIntervalSince(lastFetchDate)) * playbackRate : 0
        let value = max(0, elapsed + delta)
        return duration > 0 ? min(value, duration) : value
    }
}

@MainActor
final class NowPlayingMonitor: ObservableObject {
    @Published var info = NowPlayingInfo()
    @Published private(set) var commandError: String?
    private let bridge = MediaRemoteBridge.shared
    private let system = SystemMediaProvider.shared
    private let playerObserver = NowPlayingObserver()
    private let browserObserver = BrowserObserver()
    private let artworkFetcher = ArtworkFetcher()
    private let settings = ModuleSettings.shared
    private var cancellables = Set<AnyCancellable>()
    private var nativeTracks: [String: NowPlayingInfo] = [:]
    private var systemTrack: NowPlayingInfo?
    private var browserTrack: BrowserObserver.BrowserTrack?
    private var endTimer: Timer?
    private enum Route { case none, system, native(String), browser(BrowserObserver.BrowserTrack) }
    private var route: Route = .none

    init() {
        playerObserver.onChange = { [weak self] in self?.applyPlayer($0) }
        browserObserver.onChange = { [weak self] in
            self?.browserTrack = $0
            self?.selectSource()
        }
        system.onChange = { [weak self] in self?.applySystem($0) }
        settings.$nowPlayingEnabled.combineLatest(settings.$browserObserverEnabled, settings.$systemMediaEnabled)
            .receive(on: DispatchQueue.main).sink { [weak self] enabled, _, generic in
                guard let self else { return }
                if enabled && generic { self.system.start() } else { self.system.stop() }
                if !enabled { self.nativeTracks.removeAll(); self.browserTrack = nil }
                self.updateBrowserObservation()
                self.selectSource()
            }.store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] notification in
                guard let self, let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let id = app.bundleIdentifier else { return }
                self.nativeTracks.removeValue(forKey: id)
                if self.systemTrack?.sourceBundleID == id { self.systemTrack = nil }
                if self.browserTrack?.bundleID == id { self.browserTrack = nil }
                self.updateBrowserObservation()
                self.selectSource()
            }.store(in: &cancellables)
    }

    deinit { endTimer?.invalidate() }

    private func updateBrowserObservation() {
        if settings.nowPlayingEnabled && settings.browserObserverEnabled && !system.isChecking && systemTrack?.hasContent != true {
            browserObserver.start()
        } else {
            browserObserver.stop()
            browserTrack = nil
        }
    }

    private func applySystem(_ payload: TrackInfo.Payload?) {
        guard settings.nowPlayingEnabled, settings.systemMediaEnabled, let payload,
              let title = payload.title, !title.isEmpty,
              let bundleID = payload.bundleIdentifier, !bundleID.isEmpty else {
            systemTrack = nil
            updateBrowserObservation()
            selectSource()
            return
        }
        var snapshot = NowPlayingInfo()
        snapshot.title = title
        snapshot.artist = payload.artist ?? ""
        snapshot.album = payload.album ?? ""
        snapshot.sourceBundleID = bundleID
        snapshot.sourceIdentity = "system|\(bundleID)"
        snapshot.source = payload.applicationName ?? displayName(bundleID)
        snapshot.duration = finite((payload.durationMicros ?? 0) / 1_000_000)
        snapshot.elapsed = finite((payload.elapsedTimeMicros ?? 0) / 1_000_000)
        snapshot.isPlaying = payload.isPlaying ?? false
        snapshot.playbackRate = finite(payload.playbackRate ?? 1)
        if let timestamp = payload.timestampEpochMicros, timestamp.isFinite, timestamp > 0 {
            snapshot.lastFetchDate = Date(timeIntervalSince1970: timestamp / 1_000_000)
        } else { snapshot.lastFetchDate = Date() }
        snapshot.artwork = payload.artwork?.resizedBitmap(maxSide: 320)
        snapshot.canToggle = true
        snapshot.canSkip = true
        systemTrack = snapshot
        updateBrowserObservation()
        selectSource()
    }

    private func finite(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }

    private func applyPlayer(_ player: NowPlayingObserver.PlayerInfo) {
        guard settings.nowPlayingEnabled else { return }
        if player.title.isEmpty { nativeTracks.removeValue(forKey: player.bundleID) }
        else {
            var snapshot = NowPlayingInfo()
            snapshot.title = player.title
            snapshot.artist = player.artist
            snapshot.album = player.album
            snapshot.duration = finite(player.duration)
            snapshot.elapsed = finite(player.elapsed)
            snapshot.isPlaying = player.isPlaying
            snapshot.sourceBundleID = player.bundleID
            snapshot.sourceIdentity = "native|\(player.bundleID)"
            snapshot.source = displayName(player.bundleID)
            snapshot.lastFetchDate = Date()
            snapshot.canToggle = MediaRemoteBridge.supports(player.bundleID)
            snapshot.canSkip = snapshot.canToggle
            nativeTracks[player.bundleID] = snapshot
        }
        selectSource()
    }

    private func browserInfo(_ track: BrowserObserver.BrowserTrack) -> NowPlayingInfo {
        var snapshot = NowPlayingInfo()
        snapshot.title = track.title
        snapshot.artist = track.artist
        snapshot.album = track.album
        snapshot.duration = track.duration
        snapshot.elapsed = track.elapsed
        snapshot.playbackRate = track.playbackRate
        snapshot.isPlaying = track.isPlaying
        snapshot.source = track.source
        snapshot.sourceBundleID = track.bundleID
        snapshot.sourceIdentity = track.identity
        snapshot.pageURL = track.pageURL
        snapshot.artworkURL = track.artworkURL
        snapshot.canToggle = track.canToggle
        snapshot.lastFetchDate = track.observedAt
        return snapshot
    }

    private func selectSource() {
        guard settings.nowPlayingEnabled else { publish(NowPlayingInfo(), route: .none); return }
        let native = nativeTracks.values.sorted { $0.lastFetchDate > $1.lastFetchDate }
        if let systemTrack { publish(systemTrack, route: .system) }
        else if let playing = native.first(where: \.isActivelyPlaying) { publish(playing, route: .native(playing.sourceBundleID)) }
        else if let browserTrack, browserTrack.isPlaying { publish(browserInfo(browserTrack), route: .browser(browserTrack)) }
        else if let recent = native.first { publish(recent, route: .native(recent.sourceBundleID)) }
        else if let browserTrack { publish(browserInfo(browserTrack), route: .browser(browserTrack)) }
        else { publish(NowPlayingInfo(), route: .none) }
    }

    private func publish(_ snapshot: NowPlayingInfo, route: Route) {
        let changed = snapshot.contentIdentity != info.contentIdentity
        let artworkChanged = snapshot.artworkURL != info.artworkURL
        var next = snapshot
        if !changed, !artworkChanged, next.artwork == nil { next.artwork = info.artwork }
        self.route = route
        info = next
        if changed { commandError = nil }
        if (changed || artworkChanged), next.hasContent, snapshot.artwork == nil {
            let identity = next.contentIdentity
            artworkFetcher.fetch(title: next.title, artist: next.artist, bundleID: next.sourceBundleID,
                                 pageURL: next.pageURL, artworkURL: next.artworkURL) { [weak self] image in
                guard let self, self.info.contentIdentity == identity, self.info.artwork == nil else { return }
                self.info.artwork = image
            }
        }
        endTimer?.invalidate()
        // Il flusso di sistema gestisce anche loop, live stream e cambio traccia.
        if case .system = route { return }
        guard next.isActivelyPlaying, next.duration > 0 else { return }
        let interval = max(1, (next.duration - next.liveElapsed()) / max(0.1, next.playbackRate) + 1)
        endTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .native(let id) = self.route { self.nativeTracks.removeValue(forKey: id) }
                if case .browser = self.route { self.browserTrack = nil; self.browserObserver.pollSoon() }
                self.selectSource()
            }
        }
    }

    private func displayName(_ bundleID: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
            ?? bundleID.components(separatedBy: ".").last ?? bundleID
    }

    func openSourceApp() {
        if case .browser(let track) = route, let url = URL(string: track.pageURL),
           let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: track.bundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: info.sourceBundleID) {
            NSWorkspace.shared.open(app)
        }
    }

    func togglePlayPause() { if info.canToggle { send(info.isPlaying ? .pause : .play) } }
    func nextTrack() { if info.canSkip { send(.nextTrack) } }
    func prevTrack() { if info.canSkip { send(.prevTrack) } }

    private func send(_ command: MediaRemoteBridge.Command) {
        commandError = nil
        let identity = info.contentIdentity
        let completion: (Bool) -> Void = { [weak self] success in
            guard let self, self.info.contentIdentity == identity else { return }
            if !success { self.commandError = "Comando non disponibile per questa sorgente" }
        }
        switch route {
        case .system: completion(system.send(command, expectedBundleID: info.sourceBundleID))
        case .native(let id): bridge.send(command, fallbackBundleID: id, completion: completion)
        case .browser(let track):
            guard command == .play || command == .pause else { completion(false); return }
            browserObserver.setPlaying(command == .play, track: track, completion: completion)
        case .none: completion(false)
        }
    }
}
