import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

final class FileConverter {

    // MARK: - Available conversions

    func availableConversions(for url: URL) -> [ConversionOption] {
        let ext = url.pathExtension.lowercased()

        let imageFormats: [String: [ConversionOption]] = [
            "png":  [.init(label: "JPG",  ext: "jpg"),  .init(label: "HEIC", ext: "heic"), .init(label: "TIFF", ext: "tiff")],
            "jpg":  [.init(label: "PNG",  ext: "png"),  .init(label: "HEIC", ext: "heic"), .init(label: "TIFF", ext: "tiff")],
            "jpeg": [.init(label: "PNG",  ext: "png"),  .init(label: "HEIC", ext: "heic"), .init(label: "TIFF", ext: "tiff")],
            "heic": [.init(label: "PNG",  ext: "png"),  .init(label: "JPG",  ext: "jpg"),  .init(label: "TIFF", ext: "tiff")],
            "tiff": [.init(label: "PNG",  ext: "png"),  .init(label: "JPG",  ext: "jpg")],
            "tif":  [.init(label: "PNG",  ext: "png"),  .init(label: "JPG",  ext: "jpg")],
            "bmp":  [.init(label: "PNG",  ext: "png"),  .init(label: "JPG",  ext: "jpg")],
            "gif":  [.init(label: "PNG",  ext: "png"),  .init(label: "JPG",  ext: "jpg")],
            "webp": [.init(label: "PNG",  ext: "png"),  .init(label: "JPG",  ext: "jpg")],
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
        let dest = tempURL(for: url, newExt: toExt)
        // AVFoundation non sovrascrive file esistenti: rimuovi prima
        try? FileManager.default.removeItem(at: dest)

        let imageExts = ["png","jpg","jpeg","heic","tiff","tif","bmp","gif","webp"]
        let audioExts = ["mp3","wav","aiff","aif","m4a","caf","flac"]
        let videoExts = ["mov","mp4","m4v"]

        if imageExts.contains(ext) {
            try convertImage(url: url, to: dest, ext: toExt)
        } else if audioExts.contains(ext) || videoExts.contains(ext) {
            try await convertAV(url: url, to: dest, ext: toExt)
        } else {
            throw ConversionError.unsupported
        }
        return dest
    }

    // MARK: - Image conversion (ImageIO)

    private func convertImage(url: URL, to dest: URL, ext: String) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ConversionError.cannotReadImage }

        let uti = utiFor(ext: ext)
        guard let destination = CGImageDestinationCreateWithURL(dest as CFURL, uti as CFString, 1, nil)
        else { throw ConversionError.cannotWriteImage }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.92
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
                        let rem = AVAudioFrameCount(inputFile.length - inputFile.framePosition)
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
        session.outputURL      = dest
        session.outputFileType = fileType
        await session.export()
        if let error = session.error { throw error }
        guard session.status == .completed else { throw ConversionError.exportFailed }
    }

    // MARK: - Helpers

    private func tempURL(for url: URL, newExt: String) -> URL {
        let name = url.deletingPathExtension().lastPathComponent + "_converted.\(newExt)"
        return ModuleSettings.shared.outputDirectory.appendingPathComponent(name)
    }

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

    var errorDescription: String? {
        switch self {
        case .unsupported:          return "Formato non supportato"
        case .cannotReadImage:      return "Impossibile leggere l'immagine"
        case .cannotWriteImage:     return "Impossibile creare il file di destinazione"
        case .finalizeFailed:       return "Errore durante il salvataggio"
        case .exportSessionFailed:  return "Impossibile creare la sessione di esportazione"
        case .exportFailed:         return "Esportazione fallita"
        case .noAudioTrack:         return "Nessuna traccia audio trovata nel file"
        }
    }
}
