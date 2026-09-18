import Foundation

/// Stage exports beside their destination, then publish with an atomic move.
/// Existing files are never removed; failures leave no half-written result.
final class OutputFile {
    let temporaryURL: URL
    private let directory: URL
    private let workspace: URL
    private let name: String

    init(directory: URL, name: String) throws {
        self.directory = directory
        self.name = name
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        workspace = directory.appendingPathComponent(".dynamicisland-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: false)
        temporaryURL = workspace.appendingPathComponent(name)
    }

    deinit { try? FileManager.default.removeItem(at: workspace) }

    func publish() throws -> URL {
        let file = URL(fileURLWithPath: name)
        let base = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension.isEmpty ? "" : "." + file.pathExtension
        for suffix in 0...9999 {
            let filename = suffix == 0 ? name : "\(base) \(suffix)\(ext)"
            let destination = directory.appendingPathComponent(filename)
            do {
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                return destination
            } catch CocoaError.fileWriteFileExists { continue }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    static func write(directory: URL, name: String, body: (URL) throws -> Void) throws -> URL {
        let output = try OutputFile(directory: directory, name: name)
        try body(output.temporaryURL)
        return try output.publish()
    }
}
