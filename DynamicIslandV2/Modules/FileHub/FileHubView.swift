import SwiftUI
import UniformTypeIdentifiers

struct FileHubView: View {
    @StateObject private var vm = FileHubViewModel()
    @ObservedObject var shelf: ShelfManager
    var isDragging: Bool

    var body: some View {
        ZStack {
            switch vm.state {
            case .idle:
                idleView
            case .convertOptions(let url, let opts):
                convertOptionsView(url: url, opts: opts)
            case .processing(let label):
                processingView(label: label)
            case .done(let url, let label):
                doneView(url: url, label: label)
            case .bgRemoving:
                processingView(label: "Rimozione sfondo…")
            case .bgDone(let img, let orig):
                bgDoneView(image: img, original: orig)
            case .error(let msg):
                errorView(msg: msg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.22), value: vm.state.tag)
        .onReceive(NotificationCenter.default.publisher(for: .fileHubConvertDrop)) { notification in
            guard let url = notification.object as? URL else { return }
            let opts = vm.converter.availableConversions(for: url)
            vm.state = opts.isEmpty
                ? .error("Nessuna conversione disponibile per questo tipo di file.")
                : .convertOptions(url: url, options: opts)
        }
        .onReceive(NotificationCenter.default.publisher(for: .fileHubBGDrop)) { notification in
            guard let url = notification.object as? URL else { return }
            vm.startBGRemoval(url: url)
        }
    }

    // MARK: - Idle

    @ViewBuilder
    private var idleView: some View {
        if isDragging {
            dragModeView
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                    removal:   .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                ))
        } else {
            shelfOnlyView
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                    removal:   .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                ))
        }
    }

    // Quattro drop zone + shelf — visibile solo durante un drag
    private var dragModeView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                DropZone(icon: "tray.fill", label: "Shelf") { urls in
                    urls.forEach { ShelfManager.shared.add(url: $0) }
                }
                DropZone(icon: "arrow.triangle.2.circlepath", label: "Converti") { urls in
                    guard let url = urls.first else { return }
                    let opts = vm.converter.availableConversions(for: url)
                    vm.state = opts.isEmpty
                        ? .error("Nessuna conversione disponibile.")
                        : .convertOptions(url: url, options: opts)
                }
                DropZone(icon: "scissors", label: "Sfondo") { urls in
                    guard let url = urls.first else { return }
                    vm.startBGRemoval(url: url)
                }
                AirDropZone(tapItems: shelf.items.compactMap { $0.resolvedURL() })
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            if !shelf.items.isEmpty {
                Divider().background(Color.white.opacity(0.1))
                ShelfView(manager: shelf)
                    .frame(maxHeight: 56)
            }
        }
    }

    // Solo shelf — visibile quando si apre il notch senza trascinare
    @ViewBuilder
    private var shelfOnlyView: some View {
        if shelf.items.isEmpty {
            VStack(spacing: 5) {
                Image(systemName: "tray")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.18))
                Text("Trascina file qui per iniziare")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.22))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ShelfView(manager: shelf)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
    }

    // MARK: - Conversion options

    private func convertOptionsView(url: URL, opts: [ConversionOption]) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "doc")
                    .foregroundColor(.white.opacity(0.4))
                    .font(.system(size: 11))
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)

            Text("Converti in:")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))

            HStack(spacing: 6) {
                ForEach(opts) { opt in
                    Button(opt.label) { vm.convert(url: url, option: opt) }
                        .buttonStyle(PillButtonStyle())
                }
            }

            Button("Annulla") { vm.reset() }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
                .padding(.top, 2)
        }
        .padding(.top, 6)
    }

    // MARK: - Processing

    private func processingView(label: String) -> some View {
        VStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.7)
                .tint(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Done

    private func doneView(url: URL, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(.green)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            HStack(spacing: 8) {
                Button("Apri") { NSWorkspace.shared.open(url) }
                    .buttonStyle(PillButtonStyle())
                Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(PillButtonStyle())
                Button("Chiudi") { vm.reset() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(.top, 4)
    }

    // MARK: - BG done

    private func bgDoneView(image: NSImage, original: URL) -> some View {
        VStack(spacing: 10) {
            // Anteprima immagine + titolo
            HStack(spacing: 10) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .background(CheckerboardView())
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sfondo rimosso!")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Pronto per il salvataggio")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.35))
                }
                Spacer()
            }

            // Bottoni su riga dedicata — sempre visibili
            HStack(spacing: 10) {
                Button("Salva PNG") { vm.saveBGResult(image: image, originalURL: original) }
                    .buttonStyle(PillButtonStyle())
                Spacer()
                Button("Annulla") { vm.reset() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Error

    private func errorView(msg: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundColor(.orange)
            Text(msg)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Button("OK") { vm.reset() }
                .buttonStyle(PillButtonStyle())
        }
        .padding(.top, 4)
    }
}

// MARK: - DropZone

struct DropZone: View {
    let icon: String
    let label: String
    let onDropFiles: ([URL]) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isTargeted ? Color.white.opacity(0.18) : Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isTargeted ? Color.white.opacity(0.6) : Color.white.opacity(0.12),
                                lineWidth: isTargeted ? 1.5 : 1
                            )
                    )
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isTargeted ? .white : .white.opacity(0.5))
                    .scaleEffect(isTargeted ? 1.1 : 1.0)
            }
            .frame(height: 44)
            .animation(.interpolatingSpring(mass: 1.0, stiffness: 620, damping: 44), value: isTargeted)
            .overlay(
                DropZoneNSViewRepresentable(isTargeted: $isTargeted, onDrop: onDropFiles)
            )

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - NSViewRepresentable drag destination

struct DropZoneNSViewRepresentable: NSViewRepresentable {
    @Binding var isTargeted: Bool
    var onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> DropZoneNSView {
        let v = DropZoneNSView()
        v.onHighlight = { h in DispatchQueue.main.async { isTargeted = h } }
        v.onDrop      = onDrop
        return v
    }

    func updateNSView(_ nsView: DropZoneNSView, context: Context) {
        nsView.onDrop      = onDrop
        nsView.onHighlight = { h in DispatchQueue.main.async { isTargeted = h } }
    }
}

class DropZoneNSView: NSView {
    var onHighlight: ((Bool) -> Void)?
    var onDrop:      (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("public.file-url")])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onHighlight?(true); return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { onHighlight?(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onHighlight?(false)
        let urls = sender.draggingPasteboard
            .readObjects(forClasses: [NSURL.self],
                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        DispatchQueue.main.async {
            self.onDrop?(urls)
            // Forza il ridisegno del panel nonactivating dopo che SwiftUI ha
            // processato il cambio di stato derivante dal drop.
            DispatchQueue.main.async { self.window?.display() }
        }
        return true
    }
}

// MARK: - AirDrop helper

/// Singleton che:
/// 1. Mantiene il service vivo durante la sessione (altrimenti ARC lo dealloca subito dopo perform())
/// 2. Implementa NSSharingServiceDelegate per fornire la finestra sorgente —
///    senza questo il picker non sa dove ancorarsi e fallisce silenziosamente
final class AirDropHelper: NSObject, NSSharingServiceDelegate {
    static let shared = AirDropHelper()
    private var service: NSSharingService?

    func share(items: [URL]) {
        guard !items.isEmpty,
              let svc = NSSharingService(named: .sendViaAirDrop) else { return }
        service = svc
        svc.delegate = self
        // Avvia l'accesso alle risorse sicure prima di passarle al service
        items.forEach { _ = $0.startAccessingSecurityScopedResource() }
        // Passa come NSURL per compatibilità piena con AppKit
        let nsItems = items.map { $0 as NSURL }
        DispatchQueue.main.async { svc.perform(withItems: nsItems) }
    }

    // Indica al picker di sistemo quale finestra usare come anchor
    func sharingService(_ sharingService: NSSharingService,
                        sourceWindowForShareItems items: [Any],
                        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0 is NSPanel }
    }

    // Frame dell'origine per l'animazione di comparsa del picker
    func sharingService(_ sharingService: NSSharingService,
                        sourceFrameOnScreenForShareItem item: Any) -> NSRect {
        NSApp.windows.first { $0.isVisible && $0 is NSPanel }?.frame ?? .zero
    }
}

// MARK: - AirDrop Zone

struct AirDropZone: View {
    let tapItems: [URL]
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isTargeted ? Color.blue.opacity(0.18) : Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isTargeted ? Color.blue.opacity(0.6) : Color.white.opacity(0.12),
                                lineWidth: isTargeted ? 1.5 : 1
                            )
                    )
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isTargeted ? .blue : .white.opacity(0.5))
                    .scaleEffect(isTargeted ? 1.1 : 1.0)
            }
            .frame(height: 44)
            .animation(.interpolatingSpring(mass: 1.0, stiffness: 620, damping: 44), value: isTargeted)
            .overlay(
                AirDropNSViewRepresentable(isTargeted: $isTargeted, tapItems: tapItems)
            )
            Text("AirDrop")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }
}

struct AirDropNSViewRepresentable: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let tapItems: [URL]

    func makeNSView(context: Context) -> AirDropNSView {
        let v = AirDropNSView()
        v.onHighlight = { h in DispatchQueue.main.async { self.isTargeted = h } }
        v.tapItems    = tapItems
        return v
    }

    func updateNSView(_ nsView: AirDropNSView, context: Context) {
        nsView.onHighlight = { h in DispatchQueue.main.async { self.isTargeted = h } }
        nsView.tapItems    = tapItems
    }
}

class AirDropNSView: NSView {
    var onHighlight: ((Bool) -> Void)?
    var tapItems: [URL] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("public.file-url")])
    }
    required init?(coder: NSCoder) { fatalError() }

    // Tap senza drag → condivide i file nella shelf corrente
    override func mouseUp(with event: NSEvent) {
        AirDropHelper.shared.share(items: tapItems)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onHighlight?(true); return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { onHighlight?(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onHighlight?(false)
        let urls = sender.draggingPasteboard
            .readObjects(forClasses: [NSURL.self],
                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        DispatchQueue.main.async { AirDropHelper.shared.share(items: urls) }
        return true
    }
}

// MARK: - Checkerboard (usato come sfondo per immagini con trasparenza)

struct CheckerboardView: View {
    var tileSize: CGFloat = 4

    var body: some View {
        Canvas { ctx, size in
            let cols = Int(ceil(size.width  / tileSize))
            let rows = Int(ceil(size.height / tileSize))
            for row in 0..<rows {
                for col in 0..<cols where (row + col) % 2 == 0 {
                    ctx.fill(
                        Path(CGRect(x: CGFloat(col) * tileSize,
                                    y: CGFloat(row) * tileSize,
                                    width: tileSize, height: tileSize)),
                        with: .color(.white.opacity(0.35))
                    )
                }
            }
        }
        .background(Color.black.opacity(0.25))
    }
}

// MARK: - PillButtonStyle

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(configuration.isPressed ? 0.2 : 0.12))
            .clipShape(Capsule())
    }
}
