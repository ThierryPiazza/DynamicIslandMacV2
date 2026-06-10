import Foundation
import AppKit

// MARK: - Send-only bridge (MRMediaRemoteGetNowPlayingInfo è bloccato da TCC su macOS 14+)

final class MediaRemoteBridge {

    static let shared = MediaRemoteBridge()

    private typealias MRSendCommandFn = @convention(c) (UInt32, AnyObject?) -> Bool
    private var sendCmdFn: MRSendCommandFn?
    private var handle: UnsafeMutableRawPointer?
    private let scriptQueue = DispatchQueue(label: "opennotch.mediaremote", qos: .userInitiated)

    private init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        handle = dlopen(path, RTLD_NOW)
        if let ptr = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCmdFn = unsafeBitCast(ptr, to: MRSendCommandFn.self)
        }
    }

    enum Command: UInt32 {
        case play = 0, pause = 1, togglePlayPause = 2, nextTrack = 4, prevTrack = 5
    }

    /// Player scriptabili per il fallback AppleScript: Apple sta chiudendo
    /// MediaRemote versione dopo versione (la lettura è già morta su 14+),
    /// quindi se il comando fallisce proviamo a parlare direttamente al player.
    private static let scriptableApps: [String: String] = [
        "com.apple.Music":    "Music",
        "com.spotify.client": "Spotify",
    ]

    func send(_ cmd: Command, fallbackBundleID: String = "") {
        if sendCmdFn?(cmd.rawValue, nil) == true { return }

        guard let appName = Self.scriptableApps[fallbackBundleID] else { return }
        let verb: String
        switch cmd {
        case .play:            verb = "play"
        case .pause:           verb = "pause"
        case .togglePlayPause: verb = "playpause"
        case .nextTrack:       verb = "next track"
        case .prevTrack:       verb = "previous track"
        }
        let source = """
            if application "\(appName)" is running then
                tell application "\(appName)" to \(verb)
            end if
            """
        scriptQueue.async {
            var err: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&err)
        }
    }
}
