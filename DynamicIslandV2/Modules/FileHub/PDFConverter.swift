import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Conversioni "→ PDF" e unione di più PDF. Tutto avviene in locale:
/// - Documenti (docx/doc/rtf/rtfd/txt): letti dal sistema di testo di Cocoa
///   (lo stesso di TextEdit) e impaginati in PDF con NSPrintOperation.
/// - Presentazioni (pptx/ppt/key): delegate a Keynote, PowerPoint o LibreOffice
///   se installati — l'impaginazione di slide non ha API native.
/// - Immagini: una pagina PDF per immagine via PDFKit.
final class PDFConverter {

    static let documentExts     = ["docx", "doc", "rtf", "rtfd", "txt"]
    static let presentationExts = ["pptx", "ppt", "key"]
    static let imageExts        = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "bmp", "gif", "webp"]

    // MARK: - Documenti (Word, RTF, testo)

    /// Importa il documento con il sistema di testo di Cocoa e lo impagina in PDF.
    /// Fedeltà buona per documenti tipici; layout complessi (colonne, header/footer)
    /// vengono semplificati perché l'impaginazione la rifà TextKit.
    @MainActor
    func documentToPDF(url: URL, dest: URL) throws {
        let attributed: NSAttributedString
        do {
            attributed = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        } catch {
            // I .txt senza BOM possono far fallire l'auto-detect: riprova come testo puro
            guard url.pathExtension.lowercased() == "txt",
                  let text = (try? String(contentsOf: url, encoding: .utf8))
                          ?? (try? String(contentsOf: url, encoding: .isoLatin1))
            else { throw ConversionError.cannotReadDocument }
            attributed = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.black
            ])
        }
        try renderToPDF(attributed, dest: dest)
    }

    /// Impagina una NSAttributedString su pagine A4 e salva il PDF.
    /// NSPrintOperation gestisce la paginazione di NSTextView, inclusi
    /// allegati immagine e tabelle.
    @MainActor
    private func renderToPDF(_ attributed: NSAttributedString, dest: URL) throws {
        let printInfo = NSPrintInfo()
        printInfo.paperSize    = NSSize(width: 595.2, height: 841.8)   // A4 in punti
        printInfo.topMargin    = 56
        printInfo.bottomMargin = 56
        printInfo.leftMargin   = 56
        printInfo.rightMargin  = 56
        printInfo.horizontalPagination  = .fit
        printInfo.verticalPagination    = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered   = false
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = dest as NSURL

        let contentWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 1))
        textView.isVerticallyResizable = true
        textView.textContainer?.containerSize = NSSize(width: contentWidth,
                                                       height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(attributed)
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
        textView.sizeToFit()

        let op = NSPrintOperation(view: textView, printInfo: printInfo)
        op.showsPrintPanel    = false
        op.showsProgressPanel = false
        guard op.run() else { throw ConversionError.exportFailed }
    }

    // MARK: - Presentazioni (PowerPoint, Keynote)

    /// Converte una presentazione delegando, in ordine: Keynote → PowerPoint →
    /// LibreOffice. Sempre in locale; serve che almeno una delle tre app sia installata.
    func presentationToPDF(url: URL, dest: URL) async throws {
        // Export a private copy: closing it must never discard edits in a user-open document.
        let sourceDirectory = dest.deletingLastPathComponent().appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let source = sourceDirectory.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: source)
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }
        let isKeynoteFile = url.pathExtension.lowercased() == "key"

        if appURL(bundleID: "com.apple.iWork.Keynote") != nil {
            try await runKeynoteExport(input: source, dest: dest)
            return
        }
        // I .key li apre solo Keynote
        if !isKeynoteFile {
            if appURL(bundleID: "com.microsoft.Powerpoint") != nil {
                try await runPowerPointExport(input: source, dest: dest)
                return
            }
            if FileManager.default.isExecutableFile(atPath: Self.sofficePath) {
                try await runLibreOfficeExport(input: source, dest: dest)
                return
            }
        }
        throw ConversionError.noPresentationApp
    }

    private static let sofficePath = "/Applications/LibreOffice.app/Contents/MacOS/soffice"

    private func appURL(bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private func runKeynoteExport(input: URL, dest: URL) async throws {
        let wasRunning = isRunning(bundleID: "com.apple.iWork.Keynote")
        let script = """
        set outFile to POSIX file "\(escaped(dest.path))"
        tell application "Keynote"
            set theDoc to open POSIX file "\(escaped(input.path))"
            export theDoc to outFile as PDF
            close theDoc saving no
        end tell
        """
        try await runAppleScript(script)
        if !wasRunning { quit(bundleID: "com.apple.iWork.Keynote") }
    }

    private func runPowerPointExport(input: URL, dest: URL) async throws {
        let wasRunning = isRunning(bundleID: "com.microsoft.Powerpoint")
        let script = """
        tell application "Microsoft PowerPoint"
            open POSIX file "\(escaped(input.path))"
            set thePres to active presentation
            save thePres in (POSIX file "\(escaped(dest.path))") as save as PDF
            close thePres saving no
        end tell
        """
        try await runAppleScript(script)
        if !wasRunning { quit(bundleID: "com.microsoft.Powerpoint") }
    }

    /// soffice scrive <nome input>.pdf nella cartella indicata: converti lì e
    /// poi rinomina secondo la convenzione "_converted".
    private func runLibreOfficeExport(input: URL, dest: URL) async throws {
        let outDir = dest.deletingLastPathComponent()
        try await runProcess(Self.sofficePath, args: [
            "--headless", "--convert-to", "pdf", "--outdir", outDir.path, input.path
        ])
        let produced = outDir.appendingPathComponent(
            input.deletingPathExtension().lastPathComponent + ".pdf")
        guard FileManager.default.fileExists(atPath: produced.path) else {
            throw ConversionError.exportFailed
        }
        if produced != dest {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: produced, to: dest)
        }
    }

    private func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private func quit(bundleID: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .forEach { $0.terminate() }
    }

    /// Esegue lo script con osascript fuori processo: non blocca il main thread
    /// durante export lunghi. Il prompt TCC di automazione resta attribuito all'app.
    private func runAppleScript(_ source: String) async throws {
        try await runProcess("/usr/bin/osascript", args: ["-e", source])
    }

    private func runProcess(_ launchPath: String, args: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = args
                process.standardOutput = FileHandle.nullDevice
                let errors = Pipe()
                process.standardError = errors
                do {
                    try process.run()
                    // Drain while the process runs: waiting first can deadlock on a full pipe.
                    let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 120, execute: timeout)
                    defer { timeout.cancel() }
                    var tail = Data()
                    while let chunk = try errors.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                        tail.append(chunk)
                        if tail.count > 65536 { tail = Data(tail.suffix(65536)) }
                    }
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else {
                        throw ConversionError.scriptFailed(String(data: tail, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                    }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// Escapa backslash e doppi apici per l'inserimento in un literal AppleScript
    private func escaped(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Immagini → PDF

    func imageToPDF(url: URL, dest: URL) throws {
        let doc = PDFDocument()
        try appendImagePage(url: url, to: doc)
        guard doc.write(to: dest) else { throw ConversionError.finalizeFailed }
    }

    // MARK: - Unione in un PDF

    /// Unisce più file (PDF e/o immagini) in un unico PDF, nell'ordine di drop.
    func merge(urls: [URL], dest: URL) throws {
        let result = PDFDocument()
        for url in urls {
            if url.pathExtension.lowercased() == "pdf" {
                guard let doc = PDFDocument(url: url) else { throw ConversionError.cannotReadDocument }
                for i in 0..<doc.pageCount {
                    if let page = doc.page(at: i) {
                        result.insert(page, at: result.pageCount)
                    }
                }
            } else {
                try appendImagePage(url: url, to: result)
            }
        }
        guard result.pageCount > 0, result.write(to: dest) else {
            throw ConversionError.finalizeFailed
        }
    }

    private func appendImagePage(url: URL, to doc: PDFDocument) throws {
        guard let image = NSImage(contentsOf: url),
              let page = PDFPage(image: image)
        else { throw ConversionError.cannotReadImage }
        doc.insert(page, at: doc.pageCount)
    }
}
