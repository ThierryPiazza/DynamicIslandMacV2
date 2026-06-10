import AppKit

final class BrowserObserver {

    var onChange: ((BrowserTrack?) -> Void)?

    struct BrowserTrack {
        var title: String
        var artist: String
        var source: String
        var bundleID: String
        /// URL del tab: serve a ricavare la copertina offerta dal sito stesso
        /// (thumbnail YouTube, oEmbed Spotify/SoundCloud).
        var pageURL: String = ""
        var duration: Double
        var elapsed: Double
        var isPlaying: Bool
    }

    private var timer: Timer?
    private var isPolling = false
    private var lastTrack: BrowserTrack?
    private var lastNoTrackBundleID: String?
    private let queue = DispatchQueue(label: "opennotch.browser", qos: .utility)

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
        ("org.mozilla.firefox", "Firefox", false),
        ("com.operasoftware.Opera", "Opera", true),
    ]

    private let mediaPatterns = [
        "youtube.com/watch",
        "music.youtube.com",
        "open.spotify.com/track",
        "open.spotify.com/album",
        "music.apple.com",
        "soundcloud.com",
    ]

    private lazy var scriptsByBundleID: [String: String] = {
        Dictionary(uniqueKeysWithValues: browsers.map {
            ($0.bundleID, makeScript(appName: $0.appName, useJS: $0.useJS))
        })
    }()

    private var pollInterval: TimeInterval = 8

    func start() {
        guard timer == nil else { return }
        subscribeScreenState()
        consecutiveMisses = 0
        poll()
        schedulePoll()
    }

    func stop() {
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
        guard timer != nil, !isScreenAsleep else { return }
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

        let pause: (Notification) -> Void = { [weak self] _ in self?.isScreenAsleep = true }
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

        let t = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.poll()
            self.schedulePoll()
        }
        t.tolerance = pollInterval * 0.25
        timer = t
    }

    private func poll() {
        guard !isPolling, !isScreenAsleep else { return }

        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        guard let browser = browsers.first(where: { runningBundleIDs.contains($0.bundleID) }),
              let src = scriptsByBundleID[browser.bundleID]
        else {
            emitIfNeeded(nil, bundleID: nil)
            consecutiveMisses += 1
            pollInterval = consecutiveMisses >= missBackoffThreshold ? 30 : 10
            return
        }

        isPolling = true

        queue.async { [weak self] in
            guard let self else { return }

            var err: NSDictionary?
            let result = NSAppleScript(source: src)?.executeAndReturnError(&err)
            let raw = err == nil ? (result?.stringValue ?? "") : ""
            let track = Self.parse(raw: raw, bundleID: browser.bundleID)

            DispatchQueue.main.async {
                self.isPolling = false
                self.emitIfNeeded(track, bundleID: browser.bundleID)
                if let track {
                    self.consecutiveMisses = 0
                    self.pollInterval = track.isPlaying ? 4 : 8
                } else {
                    // Backoff: nessun tab con media da un po' → inutile
                    // scandagliare tutti i tab ogni 8 secondi.
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

    // MARK: - Script builder

    private func makeScript(appName: String, useJS: Bool) -> String {
        let patterns = mediaPatterns.map { "\"\($0)\"" }.joined(separator: ", ")

        if useJS {
            return """
            tell application "\(appName)"
                set mediaURLs to {\(patterns)}
                repeat with w in windows
                    try
                        repeat with t in tabs of w
                            try
                                set tabURL to URL of t
                                repeat with mu in mediaURLs
                                    if tabURL contains mu then
                                        set realTitle to execute t javascript "(() => { const media = document.querySelector('video, audio'); const title = (document.title || '').replaceAll('|', ' '); const url = (location.href || '').replaceAll('|', '%7C'); const duration = media && Number.isFinite(media.duration) ? media.duration : 0; const elapsed = media && Number.isFinite(media.currentTime) ? media.currentTime : 0; const paused = media ? media.paused : true; return [title, url, duration, elapsed, paused].join('|'); })()"
                                        return realTitle
                                    end if
                                end repeat
                            end try
                        end repeat
                    end try
                end repeat
                return ""
            end tell
            """
        } else if appName == "Safari" {
            return """
            tell application "Safari"
                set mediaURLs to {\(patterns)}
                repeat with w in windows
                    try
                        repeat with t in tabs of w
                            try
                                set tabURL to URL of t
                                repeat with mu in mediaURLs
                                    if tabURL contains mu then
                                        try
                                            return do JavaScript "(() => { const media = document.querySelector('video, audio'); const title = (document.title || '').replaceAll('|', ' '); const url = (location.href || '').replaceAll('|', '%7C'); const duration = media && Number.isFinite(media.duration) ? media.duration : 0; const elapsed = media && Number.isFinite(media.currentTime) ? media.currentTime : 0; const paused = media ? media.paused : true; return [title, url, duration, elapsed, paused].join('|'); })()" in t
                                        on error
                                            -- "Consenti JavaScript da Apple Events" disattivato: fallback solo titolo
                                            return name of t & "|" & tabURL & "|0|0|false"
                                        end try
                                    end if
                                end repeat
                            end try
                        end repeat
                    end try
                end repeat
                return ""
            end tell
            """
        } else {
            return """
            tell application "Firefox"
                return title of front window & "||0|0|false"
            end tell
            """
        }
    }

    // MARK: - Parse "title|url|duration|elapsed|paused"

    // Static e internal (non private): funzione pura, verificata dai test.
    static func parse(raw: String, bundleID: String) -> BrowserTrack? {
        // Alcuni browser (es. Arc) restituiscono la stringa JS già racchiusa
        // tra virgolette: vanno tolte PRIMA dello split, altrimenti finiscono
        // nel titolo e nell'ultimo campo ("true\"" non matcha mai "true").
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count > 1 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        guard !cleaned.isEmpty else { return nil }

        let parts = cleaned.components(separatedBy: "|")

        let title = Self.cleanTitle(parts[safe: 0] ?? "")
        let url = parts[safe: 1] ?? ""
        let duration = Double(parts[safe: 2] ?? "") ?? 0
        let elapsed = Double(parts[safe: 3] ?? "") ?? 0
        let paused = (parts[safe: 4] ?? "false").trimmingCharacters(in: .whitespaces) == "true"

        guard !title.isEmpty else { return nil }

        if url.contains("youtube.com/watch") ||
            url.contains("music.youtube.com") ||
            title.hasSuffix("- YouTube") {

            let clean = title
                .replacingOccurrences(of: " - YouTube", with: "")
                .replacingOccurrences(of: " • YouTube", with: "")
                .trimmingCharacters(in: .whitespaces)

            guard !clean.isEmpty, clean != "YouTube" else { return nil }

            let p = clean.components(separatedBy: " - ")
            if p.count >= 2 {
                return BrowserTrack(title: p[1...].joined(separator: " - "), artist: p[0], source: "YouTube", bundleID: bundleID, pageURL: url, duration: duration, elapsed: elapsed, isPlaying: !paused)
            }
            return BrowserTrack(title: clean, artist: "", source: "YouTube", bundleID: bundleID, pageURL: url, duration: duration, elapsed: elapsed, isPlaying: !paused)
        }

        if url.contains("open.spotify.com") || title.contains("| Spotify") {
            let stripped = title.replacingOccurrences(of: " | Spotify", with: "")
            let p = stripped.components(separatedBy: " · ")
            if p.count >= 2 {
                return BrowserTrack(title: p[0], artist: p[1], source: "Spotify Web", bundleID: bundleID, pageURL: url, duration: duration, elapsed: elapsed, isPlaying: !paused)
            }
            return BrowserTrack(title: stripped, artist: "", source: "Spotify Web", bundleID: bundleID, pageURL: url, duration: duration, elapsed: elapsed, isPlaying: !paused)
        }

        if url.contains("music.apple.com") || title.contains("Apple Music") {
            let stripped = title.replacingOccurrences(of: " - Apple Music", with: "")
            let p = stripped.components(separatedBy: " - ")
            if p.count >= 2 {
                return BrowserTrack(title: p[0], artist: p[1], source: "Apple Music", bundleID: bundleID, pageURL: url, duration: duration, elapsed: elapsed, isPlaying: !paused)
            }
            return BrowserTrack(title: stripped, artist: "", source: "Apple Music", bundleID: bundleID, pageURL: url, duration: duration, elapsed: elapsed, isPlaying: !paused)
        }

        if url.contains("soundcloud.com") || title.contains("| SoundCloud") {
            let stripped = title.replacingOccurrences(of: " | SoundCloud", with: "")
            let p = stripped.components(separatedBy: " - ")
            if p.count >= 2 {
                return BrowserTrack(title: p[1...].joined(separator: " - "), artist: p[0], source: "SoundCloud", bundleID: bundleID, pageURL: url, duration: duration, elapsed: elapsed, isPlaying: !paused)
            }
            return BrowserTrack(title: stripped, artist: "", source: "SoundCloud", bundleID: bundleID, pageURL: url, duration: duration, elapsed: elapsed, isPlaying: !paused)
        }

        return nil
    }

    private static func cleanTitle(_ s: String) -> String {
        var result = s.trimmingCharacters(in: .whitespaces)

        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count > 1 {
            result = String(result.dropFirst().dropLast())
        }

        while let range = result.range(of: #"^\(\d+\)\s*"#, options: .regularExpression) {
            result.removeSubrange(range)
        }

        return result.trimmingCharacters(in: .whitespaces)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
