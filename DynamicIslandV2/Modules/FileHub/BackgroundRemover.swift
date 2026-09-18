import AppKit
import Vision
import CoreImage

final class BackgroundRemover {

    func remove(from url: URL) async throws -> NSImage {
        // CGImageSource legge correttamente HEIC, PNG, JPG, TIFF ecc.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw BGError.invalidImage }

        guard #available(macOS 14.0, *) else { throw BGError.osNotSupported }
        return try await removeWithVision(cgImage: cgImage)
    }

    // MARK: - Vision (macOS 14+)

    @available(macOS 14.0, *)
    private func removeWithVision(cgImage: CGImage) async throws -> NSImage {
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNGenerateForegroundInstanceMaskRequest()
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    try handler.perform([request])
                    guard let result = request.results?.first else {
                        cont.resume(throwing: BGError.noSubjectFound)
                        return
                    }
                    let pixelBuffer = try result.generateMaskedImage(
                        ofInstances: result.allInstances,
                        from: handler,
                        croppedToInstancesExtent: false
                    )

                    // Renderizza esplicitamente con CIContext per preservare il canale alpha
                    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                    let context = CIContext()
                    guard let cgOut = context.createCGImage(ciImage, from: ciImage.extent) else {
                        cont.resume(throwing: BGError.renderFailed)
                        return
                    }
                    let size = NSSize(width: cgOut.width, height: cgOut.height)
                    let nsImage = NSImage(size: size)
                    nsImage.addRepresentation(NSBitmapImageRep(cgImage: cgOut))
                    cont.resume(returning: nsImage)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

enum BGError: LocalizedError {
    case invalidImage, noSubjectFound, osNotSupported, renderFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:    return "File non è un'immagine valida"
        case .noSubjectFound:  return "Nessun soggetto riconoscibile nell'immagine"
        case .osNotSupported:  return "Richiede macOS 14 o superiore"
        case .renderFailed:    return "Errore nella generazione dell'immagine"
        }
    }
}
