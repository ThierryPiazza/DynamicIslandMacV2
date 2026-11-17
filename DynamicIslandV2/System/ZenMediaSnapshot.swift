import Foundation

/// Shared wire format for the native host and app. Times are Unix seconds.
struct ZenMediaSnapshot: Codable {
    static let maxAge: TimeInterval = 10
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DynamicIsland/ZenBridge", isDirectory: true)
    }
    var version: Int
    var receivedAt: Double?
    var session: String?
    var track: Track?

    struct Track: Codable {
        var identity: String
        var title: String
        var artist: String
        var album: String
        var pageURL: String
        var artworkURL: String
        var artworkDataBase64: String?
        var duration: Double?
        var elapsed: Double?
        var playbackRate: Double
        var isPlaying: Bool
        var sampledAt: Double
        var sequence: Int

        var isValid: Bool {
            !identity.isEmpty && identity.utf8.count <= 16384 && !title.isEmpty && title.count <= 1024 &&
            artist.count <= 1024 && album.count <= 1024 && pageURL.utf8.count <= 16384 &&
            ["http", "https"].contains(URL(string: pageURL)?.scheme ?? "") &&
            (duration == nil || (duration!.isFinite && duration! > 0)) &&
            (elapsed == nil || (elapsed!.isFinite && elapsed! >= 0)) &&
            playbackRate.isFinite && playbackRate >= 0 && playbackRate <= 16 &&
            sampledAt.isFinite && sequence >= 0 && (artworkDataBase64?.utf8.count ?? 0) <= 512_000
        }
    }

    func freshTrack(at now: Date = Date()) -> Track? {
        guard version == 1, let receivedAt, receivedAt.isFinite,
              now.timeIntervalSince1970 - receivedAt >= -2,
              now.timeIntervalSince1970 - receivedAt <= Self.maxAge,
              let track, track.isValid,
              now.timeIntervalSince1970 - track.sampledAt >= -2,
              now.timeIntervalSince1970 - track.sampledAt <= Self.maxAge else { return nil }
        return track
    }
}
