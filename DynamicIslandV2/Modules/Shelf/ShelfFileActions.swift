import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Le esportazioni usano un file temporaneo e non sovrascrivono mai l'originale.
enum ShelfFileActions {
    enum Failure: LocalizedError {
        case invalidName, invalidImage, compressionFailed, destinationInsideSource
        var errorDescription: String? {
            switch self {
            case .invalidName: return "Inserisci un nome valido, senza / o : e diverso da . e .."
            case .invalidImage: return "Impossibile ridimensionare questa immagine."
            case .compressionFailed: return "Impossibile creare l'archivio ZIP."
            case .destinationInsideSource: return "Scegli nelle impostazioni una cartella di output esterna alla cartella da comprimere."
            }
        }
    }

    static func rename(_ source: URL, to name: String) throws -> URL {
        var name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"),
              !name.contains("\0") else { throw Failure.invalidName }
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        let isOrdinaryDirectory = values.isDirectory == true && values.isPackage != true
        if !isOrdinaryDirectory, !source.pathExtension.isEmpty, (name as NSString).pathExtension.isEmpty {
            // Anche "Documento." indica un nome senza estensione: evita il doppio punto.
            while name.hasSuffix(".") { name.removeLast() }
            guard !name.isEmpty else { throw Failure.invalidName }
            name += "." + source.pathExtension
        }
        let destination = source.deletingLastPathComponent().appendingPathComponent(name)
        if source == destination { return source }
        // moveItem fallisce se esiste già un file: nessuna sovrascrittura.
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
    }

    static func compress(_ source: URL, outputDirectory: URL) throws -> URL {
        let directory = try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        if directory {
            let input = source.resolvingSymlinksInPath().standardizedFileURL.path
            let output = outputDirectory.resolvingSymlinksInPath().standardizedFileURL.path
            guard output != input, !output.hasPrefix(input == "/" ? "/" : input + "/") else { throw Failure.destinationInsideSource }
        }
        return try OutputFile.write(directory: outputDirectory, name: source.deletingPathExtension().lastPathComponent + ".zip") { temporary in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            task.arguments = ["-c", "-k", "--sequesterRsrc"] + (directory ? ["--keepParent"] : []) + [source.path, temporary.path]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { throw Failure.compressionFailed }
        }
    }

    static func resize(_ source: URL, maxSide: Int, outputDirectory: URL) throws -> URL {
        guard (32...8192).contains(maxSide),
              let input = CGImageSourceCreateWithURL(source as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw Failure.invalidImage }
        let side = min(maxSide, max(width, height))
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                       kCGImageSourceCreateThumbnailWithTransform: true,
                                       kCGImageSourceThumbnailMaxPixelSize: side]
        guard let image = CGImageSourceCreateThumbnailAtIndex(input, 0, options as CFDictionary) else { throw Failure.invalidImage }
        let name = source.deletingPathExtension().lastPathComponent + "-\(side)px.png"
        return try OutputFile.write(directory: outputDirectory, name: name) { temporary in
            guard let output = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw Failure.invalidImage }
            CGImageDestinationAddImage(output, image, nil)
            guard CGImageDestinationFinalize(output) else { throw Failure.invalidImage }
        }
    }

}
