import AppKit
import Combine
import SwiftUI

enum FileHubState {
    case idle
    case convertOptions(url: URL, options: [ConversionOption])
    case mergeConfirm(urls: [URL])
    case processing(label: String)
    case done(url: URL, label: String)
    case bgRemoving
    case bgDone(image: NSImage, originalURL: URL)
    case error(String)

    var tag: Int {
        switch self {
        case .idle:            return 0
        case .convertOptions:  return 1
        case .mergeConfirm:    return 7
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

    @Published var showingShelf = false
    private var subscriptions = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: .fileHubConvertDrop)
            .receive(on: DispatchQueue.main).sink { [weak self] notification in
                let urls = (notification.object as? [URL])
                    ?? (notification.object as? URL).map { [$0] } ?? []
                self?.handleConvertDrop(urls: urls)
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .fileHubBGDrop)
            .receive(on: DispatchQueue.main).sink { [weak self] notification in
                guard let url = notification.object as? URL else { return }
                self?.startBGRemoval(url: url)
            }.store(in: &subscriptions)
    }

    private var isBusy: Bool {
        switch state {
        case .processing, .bgRemoving: return true
        default: return false
        }
    }

    let converter = FileConverter()
    private let bgRemover = BackgroundRemover()

    private func set(_ newState: FileHubState) {
        withAnimation(.easeInOut(duration: 0.22)) {
            showingShelf = false
            state = newState
        }
        // Forza ridisegno: il panel nonactivating non riceve automaticamente un
        // ciclo display dopo cambi di stato (drag drop, completamento task async).
        DispatchQueue.main.async {
            NSApp.windows.filter(\.isVisible).forEach { $0.display() }
        }
    }

    /// Smista un drop sulla zona "Converti": più PDF/immagini → proponi l'unione
    /// in un PDF; un file solo → mostra le conversioni disponibili.
    func handleConvertDrop(urls: [URL]) {
        guard !isBusy, let first = urls.first else { return }

        if urls.count > 1 {
            let mergeable = ["pdf"] + PDFConverter.imageExts
            if urls.allSatisfy({ mergeable.contains($0.pathExtension.lowercased()) }) {
                set(.mergeConfirm(urls: urls))
                return
            }
        }

        let opts = converter.availableConversions(for: first)
        if opts.isEmpty {
            let hint = first.pathExtension.lowercased() == "pdf"
                ? "Trascina più PDF insieme per unirli in uno."
                : "Nessuna conversione disponibile per questo tipo di file."
            set(.error(hint))
        } else {
            set(.convertOptions(url: first, options: opts))
        }
    }

    func convert(url: URL, option: ConversionOption) {
        guard !isBusy else { return }
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

    func mergePDFs(urls: [URL]) {
        guard !isBusy else { return }
        set(.processing(label: "Unione in corso…"))
        Task {
            do {
                let result = try await converter.mergePDFs(urls: urls)
                set(.done(url: result, label: "PDF unito (\(urls.count) file)"))
            } catch {
                set(.error(error.localizedDescription))
            }
        }
    }

    func startBGRemoval(url: URL) {
        guard !isBusy else { return }
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
        guard !isBusy else { return }
        let directory = ModuleSettings.shared.outputDirectory
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            set(.error("Impossibile esportare l’immagine"))
            return
        }
        set(.processing(label: "Salvataggio PNG…"))
        Task {
            do {
                let destination = try await Task.detached(priority: .userInitiated) {
                    try OutputFile.write(directory: directory, name: name) { url in
                        let rep = NSBitmapImageRep(cgImage: cgImage)
                        guard let png = rep.representation(using: .png, properties: [:]) else {
                            throw ConversionError.cannotWriteImage
                        }
                        try png.write(to: url)
                    }
                }.value
                set(.done(url: destination, label: "Sfondo rimosso"))
            } catch { set(.error("Salvataggio fallito: \(error.localizedDescription)")) }
        }
    }

    func reset() {
        guard !isBusy else { return }
        set(.idle)
    }
}
