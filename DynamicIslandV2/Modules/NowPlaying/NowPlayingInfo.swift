import AppKit

struct NowPlayingInfo {
    var title = ""
    var artist = ""
    var album = ""
    var artwork: NSImage?
    var artworkIsAuthoritative = false
    var duration: Double = 0
    var elapsed: Double = 0
    var hasPlaybackPosition = false
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
    var hasPlaybackTimeline: Bool { duration > 0 && hasPlaybackPosition }
    var contentIdentity: String { "\(sourceIdentity)|\(title)|\(artist)|\(album)" }

    func liveElapsed(at now: Date = Date()) -> Double {
        let delta = isPlaying ? max(0, now.timeIntervalSince(lastFetchDate)) * playbackRate : 0
        let value = max(0, elapsed + delta)
        return duration > 0 ? min(value, duration) : value
    }
}


extension NowPlayingInfo {
    init(zen track: ZenMediaSnapshot.Track) {
        self.init()
        self.title = track.title
        self.artist = track.artist
        self.album = track.album
        self.source = "Zen"
        self.sourceBundleID = "app.zen-browser.zen"
        self.sourceIdentity = "zen|\(track.identity)"
        self.pageURL = track.pageURL
        self.duration = track.duration ?? 0
        self.elapsed = track.elapsed ?? 0
        self.hasPlaybackPosition = track.elapsed != nil
        self.playbackRate = track.playbackRate
        self.isPlaying = track.isPlaying
        self.lastFetchDate = Date(timeIntervalSince1970: track.sampledAt)
        self.artworkIsAuthoritative = true
        if let encoded = track.artworkDataBase64, let data = Data(base64Encoded: encoded) {
            self.artwork = NSImage(data: data)?.resizedBitmap(maxSide: 320)
        }
    }
}
