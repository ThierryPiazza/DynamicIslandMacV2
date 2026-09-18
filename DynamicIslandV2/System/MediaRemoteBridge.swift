import AppKit

/// Comandi diretti per i player scriptabili usati come alternativa al lettore di sistema.
final class MediaRemoteBridge {
    static let shared = MediaRemoteBridge()
    enum Command: UInt32 {
        case play = 0, pause = 1, togglePlayPause = 2, nextTrack = 4, prevTrack = 5
    }
    private let queue = DispatchQueue(label: "dynamicisland.native.commands", qos: .userInitiated)
    private static let apps = ["com.apple.Music": "Music", "com.spotify.client": "Spotify"]
    static func supports(_ bundleID: String) -> Bool { apps[bundleID] != nil }

    func send(_ command: Command, fallbackBundleID: String, completion: @escaping (Bool) -> Void) {
        guard let app = Self.apps[fallbackBundleID] else { completion(false); return }
        let verb: String
        switch command {
        case .play: verb = "play"
        case .pause: verb = "pause"
        case .togglePlayPause: verb = "playpause"
        case .nextTrack: verb = "next track"
        case .prevTrack: verb = "previous track"
        }
        let script = """
        with timeout of 3 seconds
            if application "\(app)" is running then
                tell application "\(app)" to \(verb)
                return true
            end if
            return false
        end timeout
        """
        queue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
            let success = error == nil && result?.booleanValue == true
            DispatchQueue.main.async { completion(success) }
        }
    }
}
