import Foundation
import PDFKit

enum ShelfPDFActions {
    enum Failure: LocalizedError {
        case invalidPages, unreadable, emptyResult, writeFailed
        var errorDescription: String? {
            switch self {
            case .invalidPages: return "Inserisci pagine valide, per esempio 2, 4-6. I numeri devono rientrare nel PDF."
            case .unreadable: return "PDF non leggibile, vuoto o protetto. Sbloccalo prima di modificarlo."
            case .emptyResult: return "Devi conservare almeno una pagina."
            case .writeFailed: return "Impossibile salvare il PDF."
            }
        }
    }

    static func pageIndices(_ specification: String, count: Int) throws -> Set<Int> {
        var pages = Set<Int>()
        for part in specification.split(separator: ",", omittingEmptySubsequences: false) {
            let bounds = part.split(separator: "-", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard (1...2).contains(bounds.count), let lower = Int(bounds[0]), lower >= 1,
                  let upper = Int(bounds.last!), upper >= lower, upper <= count else { throw Failure.invalidPages }
            pages.formUnion((lower...upper).map { $0 - 1 })
        }
        guard !pages.isEmpty else { throw Failure.invalidPages }
        return pages
    }

    private static func read(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url), !document.isLocked,
              document.allowsDocumentAssembly, document.pageCount > 0 else { throw Failure.unreadable }
        return document
    }

    static func removePages(from url: URL, specification: String, directory: URL) throws -> URL {
        let document = try read(url)
        let pages = try pageIndices(specification, count: document.pageCount)
        guard pages.count < document.pageCount else { throw Failure.emptyResult }
        for index in pages.sorted(by: >) { document.removePage(at: index) }
        return try save(document, name: url.deletingPathExtension().lastPathComponent + "-modificato.pdf", directory: directory)
    }

    static func merge(_ urls: [URL], directory: URL) throws -> URL {
        guard urls.count > 1 else { throw Failure.unreadable }
        let documents = try urls.map(read)
        let output = PDFDocument()
        for document in documents {
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { throw Failure.unreadable }
                output.insert(page, at: output.pageCount)
            }
        }
        return try save(output, name: "PDF-uniti.pdf", directory: directory)
    }

    private static func save(_ document: PDFDocument, name: String, directory: URL) throws -> URL {
        try OutputFile.write(directory: directory, name: name) { destination in
            guard document.write(to: destination) else { throw Failure.writeFailed }
        }
    }
}
