import AppKit
import Foundation

@main
struct ZenBridgeChecks {
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
        var environment = ProcessInfo.processInfo.environment
        environment["DYNAMICISLAND_ZEN_STATE_DIRECTORY"] = directory.path
        process.environment = environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        let provider = ZenMediaProvider(directory: directory)
        var received: ZenMediaSnapshot.Track?
        provider.onChange = { received = $0 }
        func read(_ count: Int) throws -> Data {
            var data = Data()
            while data.count < count {
                let part = try output.fileHandleForReading.read(upToCount: count - data.count) ?? Data()
                precondition(!part.isEmpty, "Host stopped before acknowledgement")
                data.append(part)
            }
            return data
        }
        func send(_ track: ZenMediaSnapshot.Track?) throws {
            let body = try JSONEncoder().encode(ZenMediaSnapshot(version: 1, track: track))
            var size = UInt32(body.count).littleEndian
            var frame = withUnsafeBytes(of: &size) { Data($0) }; frame.append(body)
            // Split frames to exercise partial reads of Native Messaging headers/bodies.
            for chunk in [frame.prefix(2), frame.dropFirst(2).prefix(11), frame.dropFirst(13)] {
                try input.fileHandleForWriting.write(contentsOf: chunk)
            }
            let header = try read(4)
            let count = header.enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
            let reply = try JSONSerialization.jsonObject(with: read(count)) as! [String: Any]
            precondition(reply["ok"] as? Bool == true)
            provider.poll()
        }
        let artwork = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }.tiffRepresentation!.base64EncodedString()
        var track = ZenMediaSnapshot.Track(identity: "document|video-a", title: "Fixture A", artist: "", album: "",
            pageURL: "https://example.invalid/a", artworkURL: "https://example.invalid/cover-a.png",
            artworkDataBase64: artwork, duration: 120, elapsed: 0, playbackRate: 1.5,
            isPlaying: true, sampledAt: Date().timeIntervalSince1970, sequence: 1)
        try send(track)
        var info = NowPlayingInfo(zen: received!)
        precondition(info.hasPlaybackTimeline && info.artwork != nil)
        precondition(abs(info.liveElapsed(at: info.lastFetchDate.addingTimeInterval(2)) - 3) < 0.01)
        track.elapsed = 60; track.sequence += 1; track.sampledAt = Date().timeIntervalSince1970
        try send(track); info = NowPlayingInfo(zen: received!)
        precondition(info.elapsed == 60, "Seek not synchronized")
        track.isPlaying = false; track.sequence += 1
        try send(track); info = NowPlayingInfo(zen: received!)
        precondition(info.liveElapsed(at: info.lastFetchDate.addingTimeInterval(3)) == 60, "Paused clock advances")
        track.isPlaying = true; track.playbackRate = 2; track.sequence += 1
        try send(track); info = NowPlayingInfo(zen: received!)
        precondition(info.liveElapsed(at: info.lastFetchDate.addingTimeInterval(3)) == 66, "Resume/rate")
        track.identity = "document|video-b"; track.title = "Fixture B"
        track.artworkURL = ""; track.artworkDataBase64 = ""; track.duration = nil; track.elapsed = nil
        track.sequence += 1
        try send(track); info = NowPlayingInfo(zen: received!)
        precondition(!info.hasPlaybackTimeline && info.artwork == nil && info.artworkIsAuthoritative, "Live/missing cover retained old data")
        provider.poll(at: Date().addingTimeInterval(12))
        precondition(received == nil, "Lost heartbeat not expired")
        track.sampledAt = Date().timeIntervalSince1970 - 30; track.sequence += 1
        try send(track)
        precondition(received == nil, "Stale content revived by host receipt time")
        try send(nil)
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0)
        let state = try JSONDecoder().decode(ZenMediaSnapshot.self, from: Data(contentsOf: directory.appendingPathComponent("snapshot.json")))
        precondition(state.track == nil, "Disconnect did not clear snapshot")
        print("Native host → atomic snapshot → app provider → NowPlayingInfo: artwork, zero, seek, pause, resume, rate, live, expiry, disconnect passed")
        print("This test does not exercise Zen or the rendered app UI.")
    }
}
