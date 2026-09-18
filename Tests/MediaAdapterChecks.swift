import Foundation
import MediaRemoteAdapter

@main
struct MediaAdapterChecks {
    @MainActor static func main() async throws {
        let controller = MediaController()
        var responses = 0
        var receivedMedia = false
        var stopped = false
        controller.onTrackInfoReceived = { track in
            precondition(!stopped, "Callback dopo stopListening")
            responses += 1
            if let track {
                receivedMedia = true
                let payload = track.payload
                print("Stream source:", payload.bundleIdentifier ?? "unknown", "playing:", payload.isPlaying == true,
                      "artwork:", payload.artwork != nil)
            }
        }
        controller.startListening()
        for _ in 0..<40 {
            if responses > 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        precondition(responses > 0, "Nessuno stato iniziale dal listener")
        precondition(controller.isListening, "Il listener deve restare attivo")
        controller.stopListening()
        stopped = true
        try await Task.sleep(nanoseconds: 200_000_000)
        precondition(!controller.isListening, "Il listener non si è fermato")
        precondition(!controller.send("play", expectedBundleID: "test.player"), "Non inviare comandi dopo stop")
        stopped = false
        responses = 0
        controller.startListening()
        for _ in 0..<40 {
            if responses > 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        precondition(responses > 0 && controller.isListening, "Riavvio del listener fallito")
        controller.stopListening()
        stopped = true
        print("Listener verificato: stato iniziale, stop, riavvio. Media presenti:", receivedMedia)
    }
}
