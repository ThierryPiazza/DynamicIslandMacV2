import AppKit
import SwiftUI

class NotchPanel: NSPanel {

    init(geometry: NotchGeometry, notchState: NotchState,
         nowPlaying: NowPlayingMonitor, shelf: ShelfManager, clipboard: ClipboardMonitor,
         notes: NotesStore, activities: CompactActivityController) {
        // Usa il frame calcolato da NotchState (che include l'overhang dei corner arc
        // per i Mac con notch fisico) invece di geometry.frame nudo: garantisce che
        // i raggi siano visibili fin dal primo avvio, senza attendere un cambio di stato.
        let initialFrame = notchState.currentFrame(for: geometry)
        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        isMovable = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true

        let rootView = NotchView(geometry: geometry, notchState: notchState,
                                 nowPlaying: nowPlaying, shelf: shelf, clipboard: clipboard,
                                 notes: notes, activities: activities)
        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        // Disabilita i safe area inset che NSHostingView aggiunge automaticamente
        // quando la finestra è nella zona menu bar / notch: senza questa riga
        // SwiftUI riceve un layout offset di ~qualche pt verso il basso e il
        // bordo superiore dell'island risulta staccato dalla cima dello schermo.
        hosting.safeAreaRegions = []

        let container = DropContainerView(
            frame: NSRect(origin: .zero, size: initialFrame.size),
            notchState: notchState,
            shelf: shelf
        )
        container.embed(hosting)
        contentView = container

        // Niente redraw forzato continuo: SwiftUI/Core Animation ridisegnano solo quando cambia lo stato.
        // Questo evita wakeup costanti della CPU quando il notch è fermo.
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// macOS chiama questo metodo ogni volta che si sposta o ridimensiona il panel,
    /// incluso durante super.init. Di default, vincola il rettangolo al visibleFrame
    /// dello schermo (sotto la menu bar), abbassando il panel di qualche punto e
    /// creando un gap visivo tra la cima dello schermo e l'island.
    /// Restituiamo il rect invariato per restare esattamente dove lo posizioniamo.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

// MARK: - DropContainerView

/// Drag destination AppKit per l'intero panel.
/// Intercetta i drop di file URL da qualsiasi app (incluso Finder) anche quando il panel
/// non è la finestra attiva. I DropZoneNSView figli hanno la precedenza quando il cursore
/// è sopra di loro (AppKit sceglie la view più profonda registrata).
final class DropContainerView: NSView {
    private var hosted: NSView?
    private let notchState: NotchState
    private let shelf: ShelfManager

    init(frame: NSRect, notchState: NotchState, shelf: ShelfManager) {
        self.notchState = notchState
        self.shelf = shelf
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("public.file-url")])
    }

    required init?(coder: NSCoder) { fatalError() }

    func embed(_ view: NSView) {
        hosted = view
        addSubview(view)
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
    }

    // MARK: - Hit testing

    /// Restituisce nil per qualsiasi punto fuori dalla forma reale del notch.
    /// Questo permette a click e scroll di passare al sistema (menu bar, altre app)
    /// nelle aree trasparenti del panel, che in modalità expanded hanno angoli vuoti.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if notchState.displayState.isExpanded {
            guard notchHitPath(bottomRadius: 24).contains(point) else { return nil }
        } else {
            // Panel sempre a dimensione espansa: in compact è attiva solo la striscia del notch.
            guard notchState.compactHitRect(inPanelBounds: bounds).contains(point) else { return nil }
        }
        return super.hitTest(point)
    }

    /// CGPath che replica la forma SwiftUI: bordo superiore piatto (radius 0),
    /// bordi inferiori arrotondati. In AppKit y=0 è in basso, y=maxY è in alto
    /// (= bordo dello schermo, a filo con il bezel → radius 0).
    private func notchHitPath(bottomRadius r: CGFloat) -> CGPath {
        let height = (notchState.geometry?.frame.height ?? 32) + notchState.expandedContentHeight
        let b = CGRect(x: bounds.minX, y: bounds.maxY - height, width: bounds.width, height: height)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: b.minX, y: b.maxY))                     // top-left  (flat)
        path.addLine(to: CGPoint(x: b.maxX, y: b.maxY))                  // top-right (flat)
        path.addLine(to: CGPoint(x: b.maxX, y: b.minY + r))
        path.addArc(tangent1End: CGPoint(x: b.maxX,     y: b.minY),
                    tangent2End: CGPoint(x: b.maxX - r,  y: b.minY), radius: r)
        path.addLine(to: CGPoint(x: b.minX + r, y: b.minY))
        path.addArc(tangent1End: CGPoint(x: b.minX,     y: b.minY),
                    tangent2End: CGPoint(x: b.minX,      y: b.minY + r), radius: r)
        path.closeSubpath()
        return path
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        notchState.showDropZone()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard
            .readObjects(forClasses: [NSURL.self],
                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }

        let loc = convert(sender.draggingLocation, from: nil)
        let third = bounds.width / 3

        DispatchQueue.main.async { [self] in
            if loc.x < third {
                urls.forEach { shelf.add(url: $0) }
            } else if loc.x < third * 2 {
                // Tutti gli URL: con più PDF/immagini la zona Converti propone l'unione
                NotificationCenter.default.post(name: .fileHubConvertDrop, object: urls)
            } else if let url = urls.first {
                NotificationCenter.default.post(name: .fileHubBGDrop, object: url)
            }
            // Il panel è nonactivating: dopo un drop macOS non cicla il runloop per il
            // ridisegno. Un secondo async assicura che SwiftUI abbia già processato il
            // cambio di stato prima di forzare la rasterizzazione.
            DispatchQueue.main.async { self.window?.display() }
        }
        return true
    }
}
