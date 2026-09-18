import Foundation

@main
struct DownloadOrganizerChecks {
    static func check(_ value: Bool, line: UInt = #line) { precondition(value, "Failed at line \(line)") }

    static func main() throws {
        let fm = FileManager.default
        let workspace = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workspace) }
        let downloads = try DocumentFileOperations.createFolder(named: "Download", in: workspace)
        let documents = try DocumentFileOperations.createFolder(named: "Documenti", in: workspace)
        let client = try DocumentFileOperations.createFolder(named: "Cliente è", in: documents)
        let nested = try DocumentFileOperations.createFolder(named: "Fatture", in: client)
        try fm.createSymbolicLink(at: documents.appendingPathComponent("link"), withDestinationURL: downloads)
        check(try DocumentFileOperations.folders(in: documents).map(\.path) == [client.path])
        for invalid in ["../outside", "..", "", "a/b"] {
            do { _ = try DocumentFileOperations.createFolder(named: invalid, in: documents); fatalError("Invalid name accepted") }
            catch {}
        }

        let original = downloads.appendingPathComponent("fattura.pdf")
        try Data("original".utf8).write(to: original)
        let moved = try DocumentFileOperations.move(original, into: nested)
        check(!fm.fileExists(atPath: original.path))
        check(try Data(contentsOf: moved) == Data("original".utf8))
        try Data("different".utf8).write(to: original)
        do { _ = try DocumentFileOperations.move(moved, into: downloads); fatalError("Undo overwrote a file") }
        catch {}
        check(try Data(contentsOf: original) == Data("different".utf8))
        check(fm.fileExists(atPath: moved.path))
        try fm.removeItem(at: original)
        _ = try DocumentFileOperations.move(moved, into: downloads)
        do { _ = try DocumentFileOperations.move(client, into: nested); fatalError("Moved into descendant") }
        catch {}

        var tracker = DownloadInboxTracker()
        let now = Date()
        check(tracker.ingest(try DownloadInboxTracker.snapshot(in: downloads), at: now).isEmpty)
        let partial = downloads.appendingPathComponent("new.pdf.crdownload")
        try Data("partial".utf8).write(to: partial)
        check(tracker.ingest(try DownloadInboxTracker.snapshot(in: downloads), at: now.addingTimeInterval(6)).isEmpty)
        let final = downloads.appendingPathComponent("new.pdf")
        try fm.moveItem(at: partial, to: final)
        check(tracker.ingest(try DownloadInboxTracker.snapshot(in: downloads), at: now.addingTimeInterval(8)).isEmpty)
        try Data("still growing".utf8).write(to: final)
        check(tracker.ingest(try DownloadInboxTracker.snapshot(in: downloads), at: now.addingTimeInterval(12)).isEmpty)
        check(tracker.ingest(try DownloadInboxTracker.snapshot(in: downloads), at: now.addingTimeInterval(16)) == [final])
        check(tracker.ingest(try DownloadInboxTracker.snapshot(in: downloads), at: now.addingTimeInterval(20)).isEmpty)
        // Firefox may expose a final-name placeholder alongside its .part file.
        let placeholder = downloads.appendingPathComponent("firefox.zip")
        try Data().write(to: placeholder)
        try Data("incomplete".utf8).write(to: placeholder.appendingPathExtension("part"))
        check(try DownloadInboxTracker.snapshot(in: downloads)[placeholder] == nil)
        print("PASS: Documenti/subfolders, safe move and undo, collisions, invalid names, download baseline, temporary files, growth and deduplication")
    }
}
