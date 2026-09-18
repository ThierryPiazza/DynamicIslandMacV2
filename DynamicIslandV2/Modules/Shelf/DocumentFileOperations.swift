import Foundation

enum DocumentFileOperations {
    static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    static func folders(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]).filter {
                let values = try $0.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey])
                return values.isDirectory == true && values.isPackage != true && values.isSymbolicLink != true
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func move(_ source: URL, into directory: URL) throws -> URL {
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        let input = source.resolvingSymlinksInPath().standardizedFileURL.path
        let output = destination.resolvingSymlinksInPath().standardizedFileURL.path
        guard input != output, !output.hasPrefix(input + "/") else {
            throw NSError(domain: "Dynamic Island", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Scegli una cartella diversa, esterna al file o alla cartella da spostare."])
        }
        // FileManager refuses an existing destination, including during undo.
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
    }

    static func createFolder(named name: String, in parent: URL) throws -> URL {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
              !name.contains(":"), !name.contains("\0") else {
            throw NSError(domain: "Dynamic Island", code: 2, userInfo: [NSLocalizedDescriptionKey: "Inserisci un nome valido per la cartella."])
        }
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}

/// Directory snapshots are processed off the main thread. Existing files form a
/// baseline; new final names must remain unchanged for at least four seconds.
struct DownloadInboxTracker {
    struct Stamp: Equatable {
        let size: Int
        let modified: Date
        let identity: String
    }
    private var baseline: [URL: Stamp]?
    private var candidates: [URL: (stamp: Stamp, since: Date)] = [:]

    static func snapshot(in directory: URL) throws -> [URL: Stamp] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        let urls = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        let partials = Set(urls.filter { ["crdownload", "part", "download", "tmp"].contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent })
        var result: [URL: Stamp] = [:]
        for url in urls {
            guard !["crdownload", "part", "download", "tmp"].contains(url.pathExtension.lowercased()),
                  !partials.contains(url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            result[url] = Stamp(size: values.fileSize ?? 0, modified: values.contentModificationDate ?? .distantPast,
                                identity: String(describing: values.fileResourceIdentifier))
        }
        return result
    }

    mutating func ingest(_ snapshot: [URL: Stamp], at now: Date) -> [URL] {
        guard let previous = baseline else { baseline = snapshot; return [] }
        baseline = previous.filter { snapshot[$0.key] != nil }
        candidates = candidates.filter { snapshot[$0.key] != nil }
        var ready: [URL] = []
        for (url, stamp) in snapshot {
            if baseline?[url] == stamp { continue }
            if let candidate = candidates[url], candidate.stamp == stamp {
                if now.timeIntervalSince(candidate.since) >= 4 {
                    ready.append(url)
                    baseline?[url] = stamp
                    candidates.removeValue(forKey: url)
                }
            } else { candidates[url] = (stamp, now) }
        }
        return ready.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
