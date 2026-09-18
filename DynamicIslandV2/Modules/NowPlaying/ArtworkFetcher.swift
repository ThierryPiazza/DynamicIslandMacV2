import AppKit

/// Recupera la copertina del brano in riproduzione.
///
/// Strategia, in ordine di affidabilità:
/// 1. Player nativo (Music / Spotify): artwork esatto via AppleScript.
/// 2. Browser: copertina offerta dal sito stesso — thumbnail YouTube,
///    oEmbed per Spotify Web e SoundCloud.
/// 3. Fallback: iTunes Search API con query ripulita e scelta del
///    risultato più simile (mai il primo "a caso").
final class ArtworkFetcher {

    /// Cache e pendingCompletions sono toccate SOLO sul main thread.
    private var cache: [String: NSImage] = [:]
    /// Ordine LRU delle chiavi in cache: oltre `cacheLimit` si scarta la più vecchia.
    private var cacheOrder: [String] = []
    private let cacheLimit = 30
    /// key → lista di completion in attesa (per gestire richieste concorrenti identiche)
    private var pendingCompletions: [String: [(NSImage?) -> Void]] = [:]

    /// Tutte le copertine vengono normalizzate a questa taglia (la stessa di Spotify).
    private static let artworkSide: CGFloat = 640

    /// Coda seriale per NSAppleScript (non è thread-safe e non va eseguito sul main).
    private let scriptQueue = DispatchQueue(label: "dynamicisland.artwork", qos: .utility)

    /// URLSession dedicata con timeout aggressivo per non bloccare lo URLSession condiviso.
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest  = 8
        cfg.timeoutIntervalForResource = 15
        return URLSession(configuration: cfg)
    }()

    deinit { session.invalidateAndCancel() }

    /// Da chiamare sul main thread.
    func fetch(title: String, artist: String, bundleID: String = "", pageURL: String = "", artworkURL: String = "", completion: @escaping (NSImage?) -> Void) {
        let key = "\(bundleID)|\(pageURL)|\(artworkURL)|\(artist)–\(title)"

        // 1. Cache hit → risposta immediata (e rinfresca la posizione LRU)
        if let cached = cache[key] {
            cacheOrder.removeAll { $0 == key }
            cacheOrder.append(key)
            completion(cached)
            return
        }

        // 2. Richiesta già in corso → accoda la completion; sarà chiamata quando finisce
        if pendingCompletions[key] != nil {
            pendingCompletions[key]?.append(completion)
            return
        }

        // 3. Nuova richiesta
        pendingCompletions[key] = [completion]

        if let url = URL(string: artworkURL), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            downloadImage(from: url, key: key) { [weak self] in
                self?.fetchFromPage(key: key, title: title, artist: artist, pageURL: pageURL)
            }
            return
        }
        switch bundleID {
        case "com.apple.Music":
            fetchFromMusicApp(key: key, title: title, artist: artist)
        case "com.spotify.client":
            fetchFromSpotifyApp(key: key, title: title, artist: artist)
        default:
            fetchFromPage(key: key, title: title, artist: artist, pageURL: pageURL)
        }
    }

    // MARK: - Copertina offerta dalla pagina del browser

    private func fetchFromPage(key: String, title: String, artist: String, pageURL: String) {
        // YouTube / YouTube Music: thumbnail diretta del video, ritagliata
        // quadrata al centro così ha la stessa forma delle copertine Spotify.
        if let videoID = Self.youtubeVideoID(from: pageURL),
           let maxres = URL(string: "https://i.ytimg.com/vi/\(videoID)/maxresdefault.jpg"),
           let hq     = URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg") {
            downloadImage(from: maxres, key: key, squareCrop: true) { [weak self] in
                self?.downloadImage(from: hq, key: key, squareCrop: true) { [weak self] in
                    self?.searchITunes(key: key, title: title, artist: artist)
                }
            }
            return
        }

        // Spotify Web / SoundCloud: copertina via oEmbed (pubblico, nessun auth)
        if let endpoint = Self.oEmbedEndpoint(for: pageURL) {
            fetchOEmbedThumbnail(endpoint: endpoint, key: key) { [weak self] in
                self?.searchITunes(key: key, title: title, artist: artist)
            }
            return
        }

        searchITunes(key: key, title: title, artist: artist)
    }

    private func fetchOEmbedThumbnail(endpoint: URL, key: String, onFailure: @escaping () -> Void) {
        session.dataTask(with: endpoint) { [weak self] data, response, _ in
            guard let self else { return }
            guard Self.isOK(response),
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let thumb = json["thumbnail_url"] as? String,
                  let url = URL(string: thumb)
            else {
                onFailure()
                return
            }
            self.downloadImage(from: url, key: key, onFailure: onFailure)
        }.resume()
    }

    // Internal (non private) per essere verificabile nei test.
    static func youtubeVideoID(from pageURL: String) -> String? {
        guard !pageURL.isEmpty, let comps = URLComponents(string: pageURL) else { return nil }
        let host = (comps.host ?? "").lowercased()

        var id: String?
        if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            id = comps.queryItems?.first(where: { $0.name == "v" })?.value
        } else if host == "youtu.be" {
            id = comps.path.split(separator: "/").first.map(String.init)
        }

        guard let id,
              id.range(of: #"^[A-Za-z0-9_-]{8,16}$"#, options: .regularExpression) != nil
        else { return nil }
        return id
    }

    // Internal (non private) per essere verificabile nei test.
    static func oEmbedEndpoint(for pageURL: String) -> URL? {
        guard !pageURL.isEmpty, var comps = URLComponents(string: pageURL) else { return nil }
        // Solo scheme+host+path: i parametri (si=, t=…) confonderebbero l'oEmbed.
        comps.query = nil
        comps.fragment = nil
        guard let clean = comps.url?.absoluteString else { return nil }

        var endpoint: URLComponents?
        let host = comps.host?.lowercased() ?? ""
        guard ["https", "http"].contains(comps.scheme?.lowercased() ?? "") else { return nil }
        if host == "open.spotify.com" {
            endpoint = URLComponents(string: "https://open.spotify.com/oembed")
            endpoint?.queryItems = [URLQueryItem(name: "url", value: clean)]
        } else if host == "soundcloud.com" || host.hasSuffix(".soundcloud.com") {
            endpoint = URLComponents(string: "https://soundcloud.com/oembed")
            endpoint?.queryItems = [URLQueryItem(name: "format", value: "json"),
                                    URLQueryItem(name: "url", value: clean)]
        }
        return endpoint?.url
    }

    // MARK: - Artwork esatto dal player (AppleScript)

    private func fetchFromMusicApp(key: String, title: String, artist: String) {
        runScript("""
            if application "Music" is running then
                tell application "Music"
                    try
                        return (get data of artwork 1 of current track)
                    end try
                end tell
            end if
            return ""
            """) { [weak self] descriptor in
            guard let self else { return }
            if let data = descriptor?.data, !data.isEmpty, let image = NSImage(data: data) {
                // Music può restituire artwork enormi (3000px): normalizza subito.
                self.fulfill(key: key, image: image.resizedBitmap(maxSide: Self.artworkSide))
            } else {
                self.searchITunes(key: key, title: title, artist: artist)
            }
        }
    }

    private func fetchFromSpotifyApp(key: String, title: String, artist: String) {
        runScript("""
            if application "Spotify" is running then
                tell application "Spotify"
                    try
                        return artwork url of current track
                    end try
                end tell
            end if
            return ""
            """) { [weak self] descriptor in
            guard let self else { return }
            let urlString = descriptor?.stringValue ?? ""
            guard !urlString.isEmpty, let url = URL(string: urlString) else {
                self.searchITunes(key: key, title: title, artist: artist)
                return
            }
            self.downloadImage(from: url, key: key) { [weak self] in
                self?.searchITunes(key: key, title: title, artist: artist)
            }
        }
    }

    /// Esegue lo script su una coda dedicata; la completion arriva su quella coda.
    private func runScript(_ source: String, completion: @escaping (NSAppleEventDescriptor?) -> Void) {
        scriptQueue.async {
            var err: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
            completion(err == nil ? result : nil)
        }
    }

    // MARK: - Fallback: iTunes Search API (pubblica, nessun auth)

    private func searchITunes(key: String, title: String, artist: String) {
        let cleanTitle  = Self.simplifiedTitle(title)
        let cleanArtist = Self.simplifiedArtist(artist)
        let query = [cleanArtist, cleanTitle].filter { !$0.isEmpty }.joined(separator: " ")

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [URLQueryItem(name: "term", value: query),
                                 URLQueryItem(name: "entity", value: "song"),
                                 URLQueryItem(name: "limit", value: "5")]
        guard !query.isEmpty, let url = components.url else {
            fulfill(key: key, image: nil)
            return
        }

        // Step A: cerca il brano sull'iTunes API
        session.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }

            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]]
            else {
                self.fulfill(key: key, image: nil)
                return
            }

            // Scegli il risultato più simile a titolo+artista richiesti.
            // Senza alcuna corrispondenza meglio il placeholder di una copertina sbagliata.
            let wantTitle  = Self.tokens(cleanTitle)
            let wantArtist = Self.tokens(cleanArtist)

            let scored = results.map { result -> ([String: Any], Int) in
                let candTitle  = Self.tokens(result["trackName"]  as? String ?? "")
                let candArtist = Self.tokens(result["artistName"] as? String ?? "")
                let score = wantTitle.intersection(candTitle).count * 2
                          + wantArtist.intersection(candArtist).count
                return (result, score)
            }

            guard let best = scored.max(by: { $0.1 < $1.1 }),
                  best.1 > 0,
                  var artworkURLString = best.0["artworkUrl100"] as? String
            else {
                self.fulfill(key: key, image: nil)
                return
            }

            // Chiedi la versione ad alta risoluzione invece di 100×100
            artworkURLString = artworkURLString.replacingOccurrences(of: "100x100bb", with: "600x600bb")

            guard let imgURL = URL(string: artworkURLString) else {
                self.fulfill(key: key, image: nil)
                return
            }

            // Step B: scarica l'immagine in modo asincrono (mai Data(contentsOf:) su callback queue!)
            self.downloadImage(from: imgURL, key: key)

        }.resume()
    }

    private func downloadImage(from url: URL, key: String, squareCrop: Bool = false, onFailure: (() -> Void)? = nil) {
        session.dataTask(with: url) { [weak self] data, response, _ in
            guard let self else { return }
            // i.ytimg.com risponde 404 con un'immagine placeholder nel body:
            // senza il check sullo status la mostreremmo come copertina.
            if Self.isOK(response), let data, let image = NSImage(data: data) {
                let final = squareCrop
                    ? image.resizedBitmap(maxSide: Self.artworkSide, squareCrop: true)
                    : image.resizedBitmap(maxSide: Self.artworkSide)
                self.fulfill(key: key, image: final)
            } else if let onFailure {
                onFailure()
            } else {
                self.fulfill(key: key, image: nil)
            }
        }.resume()
    }

    private static func isOK(_ response: URLResponse?) -> Bool {
        guard let http = response as? HTTPURLResponse else { return true }
        return (200..<300).contains(http.statusCode)
    }

    /// Salva in cache (con sfratto LRU) e chiama tutte le completion in attesa.
    private func fulfill(key: String, image: NSImage?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let image {
                self.cache[key] = image
                self.cacheOrder.removeAll { $0 == key }
                self.cacheOrder.append(key)
                while self.cacheOrder.count > self.cacheLimit {
                    self.cache.removeValue(forKey: self.cacheOrder.removeFirst())
                }
            }
            let completions = self.pendingCompletions.removeValue(forKey: key) ?? []
            completions.forEach { $0(image) }
        }
    }

    // MARK: - Pulizia query

    /// Rimuove il rumore tipico dei titoli YouTube: "(Official Video)", "[4K]",
    /// "feat. X", ecc. — con questi la ricerca iTunes fallisce quasi sempre.
    /// Internal (non private) per essere verificabile nei test.
    static func simplifiedTitle(_ s: String) -> String {
        var r = s
        r = r.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#,
                                   with: " ", options: .regularExpression)
        r = r.replacingOccurrences(
            of: #"(?i)\b(official\s+(music\s+)?video|official\s+audio|lyric\s+video|lyrics|visualizer|video\s+ufficiale|testo|audio|4k|hd|mv)\b"#,
            with: " ", options: .regularExpression)
        r = r.replacingOccurrences(of: #"(?i)\b(feat\.?|ft\.?)\s.*$"#,
                                   with: " ", options: .regularExpression)
        return r.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Rimuove i suffissi dei canali YouTube auto-generati ("Artista - Topic", "ArtistaVEVO").
    /// Internal (non private) per essere verificabile nei test.
    static func simplifiedArtist(_ s: String) -> String {
        var r = s
        r = r.replacingOccurrences(of: #"(?i)\s*-\s*topic\s*$"#,
                                   with: "", options: .regularExpression)
        r = r.replacingOccurrences(of: #"(?i)vevo\s*$"#,
                                   with: "", options: .regularExpression)
        return simplifiedTitle(r)
    }

    private static func tokens(_ s: String) -> Set<String> {
        Set(s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 })
    }
}
