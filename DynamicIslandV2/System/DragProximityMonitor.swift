import AppKit

/// Espande il notch quando inizia un drag vicino alla barra del menu.
/// Rimane espanso per tutta la durata del drag, si chiude solo al mouse-up.
final class DragProximityMonitor {
    var onDragNearNotch: (() -> Void)?
    var onDragEnded: (() -> Void)?
    /// Ritorna true se il panel è già espanso (drag interno dalla shelf, ecc.)
    var isAlreadyExpanded: (() -> Bool)?

    private var dragMonitor:    Any?
    private var mouseUpMonitor: Any?

    private var isOpen       = false
    private var triggerY: CGFloat = 0   // calcolato da screen height
    /// changeCount del drag pasteboard all'ultimo evento: i window drag non lo modificano mai,
    /// i file drag lo incrementano ogni volta che Finder avvia una sessione DnD.
    private var lastDragChangeCount: Int = Int.min

    private let triggerDistance: CGFloat = 100

    func start() {
        if let screen = NSScreen.main {
            triggerY = screen.frame.height - triggerDistance
        }
        // Registra il changeCount attuale così sappiamo quando inizia un NUOVO drag
        lastDragChangeCount = NSPasteboard(name: .drag).changeCount

        dragMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .otherMouseDragged]
        ) { [weak self] _ in
            self?.handleDrag()
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .otherMouseUp]
        ) { [weak self] _ in
            self?.handleMouseUp()
        }
    }

    func stop() {
        [dragMonitor, mouseUpMonitor].compactMap { $0 }.forEach { NSEvent.removeMonitor($0) }
        dragMonitor    = nil
        mouseUpMonitor = nil
    }

    // MARK: - Private

    private func handleDrag() {
        guard !isOpen else { return }
        // Se il panel è già espanso è un drag interno (es. dalla shelf) — ignora
        if isAlreadyExpanded?() == true { return }

        let loc     = NSEvent.mouseLocation
        let screenW = NSScreen.main?.frame.width ?? 1440
        guard loc.y > triggerY,
              loc.x > screenW * 0.15,
              loc.x < screenW * 0.85 else { return }

        // I window drag NON scrivono mai nel drag pasteboard di sistema, quindi il
        // changeCount non cambia. I file drag di Finder lo incrementano ogni nuova sessione.
        // Confrontare il changeCount è l'unico modo affidabile per distinguere i due casi
        // (i dati del pasteboard persistono tra sessioni e non si possono usare come flag).
        let dragPB       = NSPasteboard(name: .drag)
        let currentCount = dragPB.changeCount
        guard currentCount != lastDragChangeCount else { return }   // finestra → esce

        // changeCount cambiato: nuova sessione DnD. Controlla che siano file.
        let fileTypes: Set<NSPasteboard.PasteboardType> = [
            .fileURL,
            NSPasteboard.PasteboardType("public.file-url"),
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        ]
        let hasFiles = (dragPB.types?.first { fileTypes.contains($0) }) != nil

        // Aggiorna sempre il contatore per non riscattare lo stesso drag
        lastDragChangeCount = currentCount
        guard hasFiles else { return }   // drag di testo, ecc. → esce

        isOpen = true
        DispatchQueue.main.async { self.onDragNearNotch?() }
    }

    private func handleMouseUp() {
        guard isOpen else { return }
        isOpen = false
        // Piccolo delay: lascia che performDragOperation completi prima di chiudere
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.onDragEnded?()
        }
    }
}
