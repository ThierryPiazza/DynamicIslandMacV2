import Foundation

@main
struct ArtworkChecks {
    static func main() {
        precondition(ArtworkFetcher.youtubeVideoID(from: "https://www.youtube.com/watch?v=abcdefghijk") == "abcdefghijk")
        precondition(ArtworkFetcher.youtubeVideoID(from: "https://youtu.be/abcdefghijk") == "abcdefghijk")
        precondition(ArtworkFetcher.youtubeVideoID(from: "https://notyoutube.com/watch?v=abcdefghijk") == nil)
        precondition(ArtworkFetcher.youtubeVideoID(from: "https://youtu.be.evil.test/abcdefghijk") == nil)
        precondition(ArtworkFetcher.oEmbedEndpoint(for: "https://open.spotify.com/track/123?si=test")?.host == "open.spotify.com")
        precondition(ArtworkFetcher.oEmbedEndpoint(for: "https://example.test/open.spotify.com/track/123") == nil)
        precondition(ArtworkFetcher.oEmbedEndpoint(for: "https://soundcloud.com/artist/track")?.host == "soundcloud.com")
        precondition(ArtworkFetcher.oEmbedEndpoint(for: "file://soundcloud.com/artist/track") == nil)
        print("PASS: identità dei servizi artwork e rifiuto di host simili.")
    }
}
