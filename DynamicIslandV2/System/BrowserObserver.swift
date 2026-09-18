import AppKit

final class BrowserObserver {

    var onChange: ((BrowserTrack?) -> Void)?

    struct BrowserTrack: Decodable {
        var title: String
        var artist: String
        var album: String
        var source: String
        var bundleID: String = ""
        var pageURL: String
        var frameURL: String
        var mediaURL: String
        var artworkURL: String
        var duration: Double
        var elapsed: Double
        var playbackRate: Double
        var isPlaying: Bool
        var canToggle: Bool
        var windowID: Int = 0
        var tabIndex: Int = 0
        var observedAt = Date()

        private enum CodingKeys: String, CodingKey {
            case title, artist, album, source, pageURL, frameURL, mediaURL, artworkURL
            case duration, elapsed, playbackRate, isPlaying, canToggle
        }
        var identity: String { "\(bundleID)|\(windowID)|\(tabIndex)|\(pageURL)|\(mediaURL)" }
    }

    private var enabled = false
    private var generation = 0
    private var pollCancellation: Progress?
    private var timer: Timer?
    private var isPolling = false
    private var lastTrack: BrowserTrack?
    private var lastNoTrackBundleID: String?
    private let queue = DispatchQueue(label: "dynamicisland.browser", qos: .utility)

    /// Poll consecutivi senza media trovato: oltre la soglia il polling rallenta.
    private var consecutiveMisses = 0
    private let missBackoffThreshold = 5
    /// Schermo bloccato o display spento: polling sospeso del tutto.
    private var isScreenAsleep = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    private let browsers: [(bundleID: String, appName: String, useJS: Bool)] = [
        ("company.thebrowser.Browser", "Arc", true),
        ("com.google.Chrome", "Google Chrome", true),
        ("com.google.Chrome.beta", "Google Chrome Beta", true),
        ("com.microsoft.edgemac", "Microsoft Edge", true),
        ("com.brave.Browser", "Brave Browser", true),
        ("com.apple.Safari", "Safari", false),
        ("com.operasoftware.Opera", "Opera", true),
    ]

    private static let mediaJS: String = {
        guard let url = Bundle.main.url(forResource: "BrowserMedia", withExtension: "js") else { return "() => null" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "() => null"
    }()

    private lazy var scriptsByBundleID: [String: String] = {
        Dictionary(uniqueKeysWithValues: browsers.map {
            ($0.bundleID, makeScript(appName: $0.appName, useJS: $0.useJS))
        })
    }()

    private var pollInterval: TimeInterval = 8

    func start() {
        guard !enabled else { return }
        enabled = true
        generation += 1
        subscribeScreenState()
        consecutiveMisses = 0
        poll()
        schedulePoll()
    }

    deinit { stop() }

    func stop() {
        pollCancellation?.cancel()
        pollCancellation = nil
        enabled = false
        generation += 1
        timer?.invalidate()
        timer = nil
        isPolling = false
        lastTrack = nil
        lastNoTrackBundleID = nil
        unsubscribeScreenState()
    }

    /// Forza un poll a breve (es. subito dopo play/pausa/next dal notch),
    /// senza aspettare il prossimo giro del timer.
    func pollSoon(after delay: TimeInterval = 0.8) {
        guard enabled, !isScreenAsleep else { return }
        consecutiveMisses = 0
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.poll()
            self.schedulePoll()
        }
        timer = t
    }

    // MARK: - Screen state (risparmio energia)

    /// A schermo bloccato o display spento il polling AppleScript è solo
    /// batteria sprecata: sospendi e riprendi al risveglio.
    private func subscribeScreenState() {
        guard workspaceObservers.isEmpty, distributedObservers.isEmpty else { return }
        let wsnc = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()

        let pause: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            self.isScreenAsleep = true
            self.timer?.invalidate()
            self.timer = nil
            self.pollCancellation?.cancel()
            self.generation += 1
            self.isPolling = false
        }
        let resume: (Notification) -> Void = { [weak self] _ in
            guard let self, self.isScreenAsleep else { return }
            self.isScreenAsleep = false
            self.pollSoon(after: 2)
        }

        workspaceObservers = [
            wsnc.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                             object: nil, queue: .main, using: pause),
            wsnc.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                             object: nil, queue: .main, using: resume),
            // L'utente passa a un browser: esci subito dal backoff,
            // così un nuovo video viene rilevato senza aspettare 30s.
            wsnc.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                             object: nil, queue: .main) { [weak self] n in
                guard let self,
                      let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let id = app.bundleIdentifier,
                      self.browsers.contains(where: { $0.bundleID == id })
                else { return }
                if self.consecutiveMisses >= self.missBackoffThreshold {
                    self.pollSoon(after: 1.5)
                }
            },
        ]
        distributedObservers = [
            dnc.addObserver(forName: .init("com.apple.screenIsLocked"),
                            object: nil, queue: .main, using: pause),
            dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"),
                            object: nil, queue: .main, using: resume),
        ]
    }

    private func unsubscribeScreenState() {
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceObservers = []
        distributedObservers = []
        isScreenAsleep = false
    }

    private func schedulePoll() {
        timer?.invalidate()
        guard enabled, !isScreenAsleep else { timer = nil; return }

        let t = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.poll()
            self.schedulePoll()
        }
        t.tolerance = pollInterval * 0.25
        timer = t
    }

    private func poll() {
        guard enabled, !isPolling, !isScreenAsleep else { return }

        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        let sources = browsers.filter { runningBundleIDs.contains($0.bundleID) }
            .compactMap { browser -> (String, String)? in
                guard let script = scriptsByBundleID[browser.bundleID] else { return nil }
                return (browser.bundleID, script)
            }
        let token = generation
        let previousIdentity = lastTrack?.identity
        let cancellation = Progress(totalUnitCount: 1)
        pollCancellation = cancellation
        isPolling = true
        queue.async { [weak self] in
            guard let self else { return }
            var tracks: [BrowserTrack] = []
            for (bundleID, script) in sources {
                if cancellation.isCancelled { break }
                var error: NSDictionary?
                let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
                guard error == nil, let raw = result?.stringValue else { continue }
                tracks.append(contentsOf: Self.parseTracks(raw: raw, bundleID: bundleID))
            }
            let track = Self.preferred(tracks, previousIdentity: previousIdentity)
            DispatchQueue.main.async {
                guard self.enabled, self.generation == token else { return }
                self.isPolling = false
                self.pollCancellation = nil
                self.emitIfNeeded(track, bundleID: track?.bundleID)
                if let track {
                    self.consecutiveMisses = 0
                    self.pollInterval = track.isPlaying ? 4 : 8
                } else {
                    self.consecutiveMisses += 1
                    self.pollInterval = self.consecutiveMisses >= self.missBackoffThreshold ? 30 : 8
                }
            }
        }
    }

    private func emitIfNeeded(_ track: BrowserTrack?, bundleID: String?) {
        guard let track else {
            guard lastTrack != nil || lastNoTrackBundleID != bundleID else { return }
            lastTrack = nil
            lastNoTrackBundleID = bundleID
            onChange?(nil)
            return
        }

        lastNoTrackBundleID = nil
        lastTrack = track

        // Emette a ogni poll, senza dedup: garantisce che pausa/stop arrivino
        // sempre al monitor e risincronizza elapsed con il valore reale del player.
        onChange?(track)
    }

    // JSON preserves quotes, Unicode and separators in arbitrary media titles.
    static func appleScriptLiteral(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    private func makeScript(appName: String, useJS: Bool) -> String {
        let expression = "JSON.stringify((\(Self.mediaJS))())"
        let execution = useJS ? "execute t javascript \(Self.appleScriptLiteral(expression))"
                              : "do JavaScript \(Self.appleScriptLiteral(expression)) in t"
        return """
        with timeout of 3 seconds
            tell application "\(appName)"
                if not running then return ""
                set output to ""
                repeat with w in windows
                    set tabNumber to 0
                    repeat with t in tabs of w
                        set tabNumber to tabNumber + 1
                        try
                            set raw to \(execution)
                            if raw is not "null" and raw is not "" then
                                set output to output & (id of w as text) & "|" & (tabNumber as text) & "|" & raw & linefeed
                            end if
                        end try
                    end repeat
                end repeat
                return output
            end tell
        end timeout
        """
    }

    static func parseTracks(raw: String, bundleID: String) -> [BrowserTrack] {
        raw.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let windowID = Int(parts[0]), let tabIndex = Int(parts[1]), tabIndex > 0,
                  let data = String(parts[2]).data(using: .utf8),
                  var track = try? JSONDecoder().decode(BrowserTrack.self, from: data),
                  !track.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  track.duration.isFinite, track.elapsed.isFinite, track.playbackRate.isFinite else { return nil }
            track.duration = max(0, track.duration)
            track.elapsed = max(0, track.elapsed)
            track.playbackRate = max(0, track.playbackRate)
            track.bundleID = bundleID
            track.windowID = windowID
            track.tabIndex = tabIndex
            return track
        }
    }

    static func preferred(_ tracks: [BrowserTrack], previousIdentity: String?) -> BrowserTrack? {
        let playing = tracks.filter(\.isPlaying)
        let candidates = playing.isEmpty ? tracks : playing
        return candidates.first { $0.identity == previousIdentity } ?? candidates.first
    }

    func setPlaying(_ playing: Bool, track: BrowserTrack, completion: @escaping (Bool) -> Void) {
        guard enabled, track.canToggle,
              let browser = browsers.first(where: { $0.bundleID == track.bundleID }) else { completion(false); return }
        let token = generation
        let args = ["action": playing ? "play" : "pause", "pageURL": track.pageURL,
                    "frameURL": track.frameURL, "mediaURL": track.mediaURL]
        guard let data = try? JSONSerialization.data(withJSONObject: args), let json = String(data: data, encoding: .utf8) else {
            completion(false); return
        }
        let expression = "Boolean((\(Self.mediaJS))(\(json)))"
        let execution = browser.useJS ? "execute t javascript \(Self.appleScriptLiteral(expression))"
                                      : "do JavaScript \(Self.appleScriptLiteral(expression)) in t"
        let script = """
        with timeout of 3 seconds
            tell application "\(browser.appName)"
                if not running then return false
                set w to first window whose id is \(track.windowID)
                set t to tab \(track.tabIndex) of w
                return \(execution)
            end tell
        end timeout
        """
        queue.async { [weak self] in
            var error: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
            let success = error == nil && result?.booleanValue == true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.enabled, self.generation == token else { return }
                completion(success)
                self.pollSoon()
            }
        }
    }
}
