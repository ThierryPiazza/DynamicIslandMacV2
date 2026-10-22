import SwiftUI
import Translation
import Speech
import ImageIO
import UniformTypeIdentifiers

struct ShelfSmartActions: View {
    @ObservedObject private var editSettings = ModuleSettings.shared
    @ObservedObject var manager: ShelfManager
    @State private var selected = Set<UUID>()
    @State private var pagesToRemove = ""
    @State private var prefix = "File"
    @State private var message = "Seleziona i file per vedere le azioni disponibili."
    @State private var busy = false
    @State private var translationText = ""
    @State private var speechTask: SFSpeechRecognitionTask?
    private var items: [ShelfItem] { manager.items.filter { selected.contains($0.id) } }
    private var first: URL? { items.first?.resolvedURL() }
    private var type: UTType? { first.flatMap { UTType(filenameExtension: $0.pathExtension) } }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Salvataggio modifiche", selection: $editSettings.replaceEditedOriginal) {
                Text("Salva una copia").tag(false)
                Text("Modifica originale").tag(true)
            }.pickerStyle(.segmented).disabled(busy)
            Text("OCR, trascrizione, ZIP e unione PDF creano sempre un nuovo file.").font(.caption)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(manager.items) { item in
                        Button {
                            if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                        } label: {
                            Label(item.displayName, systemImage: selected.contains(item.id) ? "checkmark.circle.fill" : "doc")
                                .lineLimit(1).frame(maxWidth: 140)
                                .padding(.horizontal, 9).padding(.vertical, 7)
                                .background(selected.contains(item.id) ? ModuleSettings.shared.accentColor.opacity(0.25) : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
            }.disabled(busy)
            .onHover { manager.isHoveringActionFiles = $0 }
            .onDisappear { manager.isHoveringActionFiles = false }
            HStack {
                Button("Seleziona tutti") { selected = Set(manager.items.map(\.id)) }
                Button("Crea ZIP") { run { urls, directory in
                    let stage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: stage) }
                    for (index, url) in urls.enumerated() {
                        let target = stage.appendingPathComponent("\(index + 1)-" + url.lastPathComponent)
                        try FileManager.default.copyItem(at: url, to: target)
                    }
                    return try ShelfFileActions.compress(stage, outputDirectory: directory)
                } }
            }.disabled(busy || items.isEmpty)
            if !items.isEmpty, items.allSatisfy({ URL(fileURLWithPath: $0.path).pathExtension.lowercased() == "pdf" }) {
                if items.count == 1 {
                    HStack {
                        TextField("Pagine da eliminare: 2, 4-6", text: $pagesToRemove)
                            .textFieldStyle(.roundedBorder)
                        Button("Elimina pagine") {
                            let specification = pagesToRemove
                            run(editOriginal: true) { urls, directory in
                                try ShelfPDFActions.removePages(from: urls[0], specification: specification, directory: directory)
                            }
                        }.disabled(pagesToRemove.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.disabled(busy)
                    Text("Numerazione da 1. Salva una nuova copia del PDF.").font(.caption)
                } else {
                    Button("Unisci \(items.count) PDF") { run { urls, directory in
                        try ShelfPDFActions.merge(urls, directory: directory)
                    } }.disabled(busy)
                    Text("Ordine di unione: " + items.map(\.displayName).joined(separator: " → "))
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
            if items.count > 1 {
                HStack {
                    TextField("Prefisso", text: $prefix)
                    Button(editSettings.replaceEditedOriginal ? "Rinomina originali" : "Crea copie numerate") {
                        let name = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty, !name.contains("/"), !name.contains(":"), !name.contains("\0") else { message = "Inserisci un prefisso valido"; return }
                        if editSettings.replaceEditedOriginal {
                            for (index, item) in items.enumerated() {
                                guard let url = item.resolvedURL() else { continue }
                                let suffix = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
                                manager.rename(item, name: name + String(format: "-%03d", index + 1) + suffix)
                            }
                            message = "Rinomina avviata. Gli eventuali errori vengono mostrati nella Shelf."
                            return
                        }
                        run { urls, directory in
                            var last: URL?
                            for (index, url) in urls.enumerated() {
                                let suffix = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
                                last = try OutputFile.write(directory: directory, name: name + String(format: "-%03d", index + 1) + suffix) {
                                    try FileManager.default.copyItem(at: url, to: $0)
                                }
                            }
                            return last!
                        }
                    }
                }.disabled(busy)
                Text(editSettings.replaceEditedOriginal ? "Gli originali verranno rinominati nella loro cartella." : "Gli originali restano nella loro posizione.").font(.caption)
            }
            if items.count == 1, type?.conforms(to: .image) == true {
                HStack {
                    Button("Estrai testo") { run { urls, directory in try await FileConverter(outputDirectory: directory).convert(url: urls[0], toExt: "txt") } }
                    Button("Comprimi immagine · JPEG") { run(editOriginal: true) { urls, directory in
                        guard let source = CGImageSourceCreateWithURL(urls[0] as CFURL, nil),
                              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1920] as CFDictionary) else { throw ConversionError.cannotReadImage }
                        let bitmap = NSBitmapImageRep(cgImage: image)
                        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.65]) else { throw ConversionError.cannotWriteImage }
                        return try OutputFile.write(directory: directory, name: urls[0].deletingPathExtension().lastPathComponent + "-compresso.jpg") { try data.write(to: $0) }
                    } }
                }.disabled(busy)
                Text("JPEG: qualità 65%, lato massimo 1920 px; formato senza trasparenza.").font(.caption)
            }
            if items.count == 1, type?.conforms(to: .audio) == true {
                Button("Trascrivi audio in italiano") { transcribe() }.disabled(busy)
                Text("Richiede il riconoscimento vocale italiano disponibile sul Mac.").font(.caption)
            }
            if items.count == 1, type?.conforms(to: .text) == true {
                Button("Leggi testo da tradurre") {
                    guard let first else { return }
                    do { translationText = try String(contentsOf: first, encoding: .utf8) }
                    catch { message = error.localizedDescription }
                }
                if #available(macOS 15.0, *) {
                    ShelfTranslationView(text: translationText)
                } else {
                    Text("La traduzione integrata richiede macOS 15 o successivo.").font(.caption)
                }
            }
            if busy { ProgressView().controlSize(.small) }
            Text(message).font(.callout).textSelection(.enabled)
        }.padding(8)
        }
        .font(.system(size: 11))
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(ModuleSettings.shared.accentColor)
        .onAppear { if let first = manager.items.first { selected = [first.id] } }
    }

    private func run(editOriginal: Bool = false, _ action: @escaping ([URL], URL) async throws -> URL) {
        let urls = items.compactMap { $0.resolvedURL() }
        guard urls.count == items.count, !urls.isEmpty else { message = "Uno dei file non è più disponibile"; return }
        let directory = ModuleSettings.shared.outputDirectory
        let replace = editOriginal && editSettings.replaceEditedOriginal
        let originalItem = items.first
        busy = true
        message = "Elaborazione…"
        Task {
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    let access = urls.filter { $0.startAccessingSecurityScopedResource() }
                    defer { access.forEach { $0.stopAccessingSecurityScopedResource() } }
                    let result = try await action(urls, directory)
                    return try FileEditResult.finish(result, source: urls[0], replace: replace)
                }.value
                if replace, let originalItem { manager.remove(originalItem) }
                manager.add(url: output)
                message = "Salvato: " + output.lastPathComponent
            } catch { message = error.localizedDescription }
            busy = false
        }
    }

    private func transcribe() {
        guard let url = first else { return }
        busy = true
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized, let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "it-IT")), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
                    message = "Riconoscimento locale non disponibile o autorizzazione negata."
                    busy = false
                    return
                }
                let request = SFSpeechURLRecognitionRequest(url: url)
                request.requiresOnDeviceRecognition = true
                request.shouldReportPartialResults = false
                speechTask = recognizer.recognitionTask(with: request) { result, error in
                    DispatchQueue.main.async {
                        if let result, result.isFinal {
                            do {
                                let output = try OutputFile.write(directory: ModuleSettings.shared.outputDirectory, name: url.deletingPathExtension().lastPathComponent + "-trascrizione.txt") {
                                    try result.bestTranscription.formattedString.write(to: $0, atomically: true, encoding: .utf8)
                                }
                                manager.add(url: output)
                                message = "Trascrizione salvata."
                            } catch { message = error.localizedDescription }
                            busy = false
                            speechTask = nil
                        } else if let error {
                            message = error.localizedDescription
                            busy = false
                            speechTask = nil
                        }
                    }
                }
            }
        }
    }
}

@available(macOS 15.0, *)
private struct ShelfTranslationView: View {
    let text: String
    @State private var target = "en"
    @State private var configuration: TranslationSession.Configuration?
    @State private var result = ""
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("Traduci in", selection: $target) {
                    Text("Inglese").tag("en")
                    Text("Italiano").tag("it")
                    Text("Francese").tag("fr")
                    Text("Tedesco").tag("de")
                    Text("Spagnolo").tag("es")
                }
                Button("Traduci") {
                    configuration = .init(source: nil, target: Locale.Language(identifier: target))
                    configuration?.invalidate()
                }.disabled(text.isEmpty)
            }
            ScrollView { Text(result).textSelection(.enabled) }.frame(maxHeight: 100)
            Button("Copia traduzione") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string) }.disabled(result.isEmpty)
        }
        .translationTask(configuration) { session in
            do { result = try await session.translate(text).targetText }
            catch { result = error.localizedDescription }
        }
    }
}
