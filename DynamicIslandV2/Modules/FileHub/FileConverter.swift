import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

final class FileConverter {
    private let outputDirectory: URL?

    init(outputDirectory: URL? = nil) { self.outputDirectory = outputDirectory }

    private func destinationDirectory() async -> URL {
        if let outputDirectory { return outputDirectory }
        return await MainActor.run { ModuleSettings.shared.outputDirectory }
    }


    let pdfConverter = PDFConverter()

    // MARK: - Available conversions

    func availableConversions(for url: URL) -> [ConversionOption] {
        let ext = url.pathExtension.lowercased()
        let pdf = ConversionOption(label: "PDF", ext: "pdf")

        // Documenti e presentazioni → solo PDF
        if PDFConverter.documentExts.contains(ext) || PDFConverter.presentationExts.contains(ext) {
            return [pdf]
        }

        let imageFormats: [String: [ConversionOption]] = [
            "png":  [.init(label: "JPG",  ext: "jpg"),  .init(label: "HEIC", ext: "heic"), .init(label: "TIFF", ext: "tiff"), pdf],
            "jpg":  [.init(label: "PNG",  ext: "png"),  .init(label: "HEIC", ext: "heic"), .init(label: "TIFF", ext: "tiff"), pdf],
            "jpeg": [.init(label: "PNG",  ext: "png"),  .init(label: "HEIC", ext: "heic"), .init(label: "TIFF", ext: "tiff"), pdf],
            "heic": [.init(label: "PNG",  ext: "png"),  .init(label: "JPG",  ext: "jpg"),  .init(label: "TIFF", ext: "tiff"), pdf],
            "tiff": [.init(label: "PNG",  ext: "png"),  .init(label: "JPG",  ext: "jpg"),  pdf],
            "tif":  [.init(label: "PNG",  ext: "png"),  .init(label: "JPG",  ext: "jpg"),  pdf],
            "bmp":  [.init(label: "PNG",  ext: "png"),  .init(label: "JPG",  ext: "jpg"),  pdf],
            "gif":  [.init(label: "PNG",  ext: "png"),  .init(label: "JPG",  ext: "jpg"),  pdf],
            "webp": [.init(label: "PNG",  ext: "png"),  .init(label: "JPG",  ext: "jpg"),  pdf],
        ]

        let audioFormats: [String: [ConversionOption]] = [
            "mp3":  [.init(label: "WAV",  ext: "wav"),  .init(label: "AIFF", ext: "aiff"), .init(label: "M4A", ext: "m4a")],
            "wav":  [.init(label: "M4A",  ext: "m4a"),  .init(label: "AIFF", ext: "aiff")],
            "aiff": [.init(label: "WAV",  ext: "wav"),  .init(label: "M4A",  ext: "m4a")],
            "aif":  [.init(label: "WAV",  ext: "wav"),  .init(label: "M4A",  ext: "m4a")],
            "m4a":  [.init(label: "WAV",  ext: "wav"),  .init(label: "AIFF", ext: "aiff")],
            "caf":  [.init(label: "WAV",  ext: "wav"),  .init(label: "M4A",  ext: "m4a")],
            "flac": [.init(label: "WAV",  ext: "wav"),  .init(label: "M4A",  ext: "m4a")],
        ]

        let videoFormats: [String: [ConversionOption]] = [
            "mov": [.init(label: "MP4", ext: "mp4")],
            "mp4": [.init(label: "MOV", ext: "mov")],
            "m4v": [.init(label: "MP4", ext: "mp4"), .init(label: "MOV", ext: "mov")],
        ]

        return imageFormats[ext] ?? audioFormats[ext] ?? videoFormats[ext] ?? []
    }

    // MARK: - Convert

    func convert(url: URL, toExt: String) async throws -> URL {
        let ext = url.pathExtension.lowercased()
        let directory = await destinationDirectory()
        let output = try OutputFile(directory: directory,
                                    name: url.deletingPathExtension().lastPathComponent + "_converted.\(toExt)")
        let dest = output.temporaryURL

        let imageExts = ["png","jpg","jpeg","heic","tiff","tif","bmp","gif","webp"]
        let audioExts = ["mp3","wav","aiff","aif","m4a","caf","flac"]
        let videoExts = ["mov","mp4","m4v"]

        if toExt == "pdf" {
            if imageExts.contains(ext) {
                try pdfConverter.imageToPDF(url: url, dest: dest)
            } else if PDFConverter.documentExts.contains(ext) {
                try await pdfConverter.documentToPDF(url: url, dest: dest)
            } else if PDFConverter.presentationExts.contains(ext) {
                try await pdfConverter.presentationToPDF(url: url, dest: dest)
            } else {
                throw ConversionError.unsupported
            }
        } else if imageExts.contains(ext) {
            try convertImage(url: url, to: dest, ext: toExt)
        } else if audioExts.contains(ext) || videoExts.contains(ext) {
            try await convertAV(url: url, to: dest, ext: toExt)
        } else {
            throw ConversionError.unsupported
        }
        return try output.publish()
    }

    // MARK: - Merge PDF

    /// Unisce più PDF (e/o immagini) in un unico PDF nella cartella di output.
    func mergePDFs(urls: [URL]) async throws -> URL {
        guard let first = urls.first else { throw ConversionError.unsupported }
        let name = first.deletingPathExtension().lastPathComponent + "_unito.pdf"
        let directory = await destinationDirectory()
        let output = try OutputFile(directory: directory, name: name)
        let dest = output.temporaryURL
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try PDFConverter().merge(urls: urls, dest: dest)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
        return try output.publish()
    }

    // MARK: - Image conversion (ImageIO)

    private func convertImage(url: URL, to dest: URL, ext: String) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ConversionError.cannotReadImage }

        let uti = utiFor(ext: ext)
        guard let destination = CGImageDestinationCreateWithURL(dest as CFURL, uti as CFString, 1, nil)
        else { throw ConversionError.cannotWriteImage }

        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.92,
            kCGImagePropertyOrientation: sourceProperties?[kCGImagePropertyOrientation] ?? 1
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.finalizeFailed }
    }

    // MARK: - Audio/Video conversion (AVFoundation)

    private func convertAV(url: URL, to dest: URL, ext: String) async throws {
        switch ext {
        case "wav", "aiff":
            // AVAssetExportPresetPassthrough non può transcodificare MP3 compresso
            // in PCM (formato atteso da WAV/AIFF). Usiamo AVAssetReader + AVAssetWriter
            // per decodificare esplicitamente a LinearPCM.
            try await convertToPCM(url: url, to: dest, ext: ext)
        case "m4a":
            try await exportSession(url: url, to: dest,
                                    preset: AVAssetExportPresetAppleM4A, fileType: .m4a)
        case "mp4":
            try await exportSession(url: url, to: dest,
                                    preset: AVAssetExportPresetHighestQuality, fileType: .mp4)
        case "mov":
            try await exportSession(url: url, to: dest,
                                    preset: AVAssetExportPresetHighestQuality, fileType: .mov)
        default:
            throw ConversionError.unsupported
        }
    }

    /// Decodifica qualsiasi sorgente audio compressa (MP3, AAC…) e scrive WAV o AIFF PCM 16-bit.
    /// Usa AVAudioFile che gestisce internamente decodifica e conversione di formato,
    /// evitando la complessità (e i crash) di AVAssetReader+AVAssetWriter.
    private func convertToPCM(url: URL, to dest: URL, ext: String) async throws {
        // Sposta l'I/O sincrono su una coda in background — non blocca il main thread
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // AVAudioFile decodifica MP3/AAC → float32 PCM de-interleaved
                    let inputFile = try AVAudioFile(forReading: url)
                    let fmt = inputFile.processingFormat   // float32, non-interleaved

                    // File di output: PCM 16-bit — WAV little-endian, AIFF big-endian
                    let outSettings: [String: Any] = [
                        AVFormatIDKey:             Int(kAudioFormatLinearPCM),
                        AVSampleRateKey:           fmt.sampleRate,
                        AVNumberOfChannelsKey:     Int(fmt.channelCount),
                        AVLinearPCMBitDepthKey:    16,
                        AVLinearPCMIsFloatKey:     false,
                        AVLinearPCMIsBigEndianKey: (ext == "aiff")
                    ]
                    // commonFormat .pcmFormatFloat32 → buffer in memoria = float32
                    // AVAudioFile converte automaticamente a int16 quando scrive su disco
                    let outputFile = try AVAudioFile(
                        forWriting: dest,
                        settings: outSettings,
                        commonFormat: .pcmFormatFloat32,
                        interleaved: false
                    )

                    let chunkSize: AVAudioFrameCount = 65536
                    guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: chunkSize) else {
                        throw ConversionError.exportFailed
                    }

                    while inputFile.framePosition < inputFile.length {
                        let rem = AVAudioFrameCount(min(AVAudioFramePosition(chunkSize), inputFile.length - inputFile.framePosition))
                        try inputFile.read(into: buf, frameCount: min(chunkSize, rem))
                        guard buf.frameLength > 0 else { break }
                        try outputFile.write(from: buf)
                    }

                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func exportSession(url: URL, to dest: URL,
                               preset: String, fileType: AVFileType) async throws {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset)
        else { throw ConversionError.exportSessionFailed }
        if #available(macOS 15.0, *) {
            try await session.export(to: dest, as: fileType)
        } else {
            session.outputURL = dest
            session.outputFileType = fileType
            await session.export()
            if let error = session.error { throw error }
            guard session.status == .completed else { throw ConversionError.exportFailed }
        }
    }

    // MARK: - Helpers

    private func utiFor(ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return UTType.jpeg.identifier
        case "png":         return UTType.png.identifier
        case "heic":        return UTType.heic.identifier
        case "tiff", "tif": return UTType.tiff.identifier
        case "bmp":         return UTType.bmp.identifier
        case "gif":         return UTType.gif.identifier
        default:            return UTType.png.identifier
        }
    }
}

enum ConversionError: LocalizedError {
    case unsupported, cannotReadImage, cannotWriteImage, finalizeFailed
    case exportSessionFailed, exportFailed, noAudioTrack
    case cannotReadDocument, noPresentationApp
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported:          return "Formato non supportato"
        case .cannotReadImage:      return "Impossibile leggere l'immagine"
        case .cannotWriteImage:     return "Impossibile creare il file di destinazione"
        case .finalizeFailed:       return "Errore durante il salvataggio"
        case .exportSessionFailed:  return "Impossibile creare la sessione di esportazione"
        case .exportFailed:         return "Esportazione fallita"
        case .noAudioTrack:         return "Nessuna traccia audio trovata nel file"
        case .cannotReadDocument:   return "Impossibile leggere il documento"
        case .noPresentationApp:    return "Per convertire le presentazioni serve Keynote (gratuito), PowerPoint o LibreOffice"
        case .scriptFailed(let msg):
            return msg.isEmpty ? "Conversione fallita" : "Conversione fallita: \(msg)"
        }
    }
}
