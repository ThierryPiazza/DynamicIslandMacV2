import Foundation

/// Commits a completed edit beside its source. A format change keeps the correct extension.
enum FileEditResult {
    static func finish(_ result: URL, source: URL, replace: Bool) throws -> URL {
        guard replace else { return result }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let target = source.deletingPathExtension().appendingPathExtension(result.pathExtension)
        let fm = FileManager.default
        if target.standardizedFileURL == source.standardizedFileURL {
            // Stage on the same volume before the atomic replacement.
            let stage = source.deletingLastPathComponent().appendingPathComponent(".edit-" + UUID().uuidString)
            try fm.copyItem(at: result, to: stage)
            defer { try? fm.removeItem(at: stage) }
            _ = try fm.replaceItemAt(source, withItemAt: stage)
        } else {
            // Never overwrite an unrelated file with the new extension.
            try fm.copyItem(at: result, to: target)
            do { try fm.trashItem(at: source, resultingItemURL: nil) }
            catch { try? fm.removeItem(at: target); throw error }
        }
        try? fm.removeItem(at: result)
        return target
    }
}
