import Foundation

@main
struct ObserveZenBridge {
    @MainActor static func main() async throws {
        let provider = ZenMediaProvider()
        provider.onChange = { track in
            guard let track else { print("{\"connected\":false}"); return }
            let info = NowPlayingInfo(zen: track)
            let fields: [String: Any] = [
                "connected": true, "identityHash": String(track.identity.hashValue),
                "duration": track.duration as Any? ?? NSNull(), "position": track.elapsed as Any? ?? NSNull(),
                "rate": info.playbackRate, "playing": info.isPlaying,
                "timeline": info.hasPlaybackTimeline, "artwork": info.artwork != nil,
                "sampleAge": Date().timeIntervalSince(info.lastFetchDate)
            ]
            if let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
               let text = String(data: data, encoding: .utf8) { print(text); fflush(stdout) }
        }
        provider.start()
        try await Task.sleep(nanoseconds: 180_000_000_000)
        provider.stop()
    }
}
