import AppKit
import Combine
import SwiftUI

struct ConversionOption: Identifiable {
    let id = UUID()
    let label: String   // "JPG", "WAV"…
    let ext: String     // estensione output
}

enum FileHubState {
    case idle
    case convertOptions(url: URL, options: [ConversionOption])
    case processing(label: String)
    case done(url: URL, label: String)
    case bgRemoving
    case bgDone(image: NSImage, originalURL: URL)
    case error(String)

    var tag: Int {
        switch self {
        case .idle:            return 0
        case .convertOptions:  return 1
        case .processing:      return 2
        case .done:            return 3
        case .bgRemoving:      return 4
        case .bgDone:          return 5
        case .error:           return 6
        }
    }
}

@MainActor
final class FileHubViewModel: ObservableObject {
    @Published var state: FileHubState = .idle

    let converter = FileConverter()
    private let bgRemover = BackgroundRemover()

    private func set(_ newState: FileHubState) {
        withAnimation(.easeInOut(duration: 0.22)) { state = newState }
        // Forza ridisegno: il panel nonactivating non riceve automaticamente un
        // ciclo display dopo cambi di stato (drag drop, completamento task async).
        DispatchQueue.main.async {
            NSApp.windows.filter(\.isVisible).forEach { $0.display() }
        }
    }

    func convert(url: URL, option: ConversionOption) {
        set(.processing(label: "Conversione in corso…"))
        Task {
            do {
                let result = try await converter.convert(url: url, toExt: option.ext)
                set(.done(url: result, label: "Convertito in \(option.label)"))
            } catch {
                set(.error(error.localizedDescription))
            }
        }
    }

    func startBGRemoval(url: URL) {
        let imageExts = ["png","jpg","jpeg","heic","tiff","webp","bmp"]
        guard imageExts.contains(url.pathExtension.lowercased()) else {
            set(.error("Formato non supportato.\nUsa PNG, JPG, HEIC o TIFF."))
            return
        }
        set(.bgRemoving)
        Task {
            do {
                let result = try await bgRemover.remove(from: url)
                set(.bgDone(image: result, originalURL: url))
            } catch {
                set(.error(error.localizedDescription))
            }
        }
    }

    func saveBGResult(image: NSImage, originalURL: URL) {
        let name = originalURL.deletingPathExtension().lastPathComponent + "_nobg.png"
        let dest = ModuleSettings.shared.outputDirectory.appendingPathComponent(name)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            set(.error("Impossibile esportare l'immagine"))
            return
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            set(.error("Impossibile creare il PNG"))
            return
        }
        do {
            try png.write(to: dest)
            set(.done(url: dest, label: "Sfondo rimosso"))
        } catch {
            set(.error("Salvataggio fallito: \(error.localizedDescription)"))
        }
    }

    func reset() { set(.idle) }
}
