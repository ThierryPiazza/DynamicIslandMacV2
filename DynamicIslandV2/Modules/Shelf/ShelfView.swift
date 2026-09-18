import SwiftUI
import QuickLookThumbnailing
import UniformTypeIdentifiers

struct ShelfView: View {
    @ObservedObject var manager: ShelfManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(manager.items) { item in
                    ShelfItemView(item: item, manager: manager,
                                  onOpen:   { manager.open(item) },
                                  onRemove: { manager.remove(item) })
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - ShelfItemView

struct ShelfItemView: View {
    let item: ShelfItem
    @ObservedObject var manager: ShelfManager
    let onOpen:   () -> Void
    let onRemove: () -> Void

    @State private var thumbnail: NSImage? = nil
    @State private var isHovered = false
    @StateObject private var dragSession = ShelfDragSession()
    @State private var thumbnailRequest: QLThumbnailGenerator.Request?
    @State private var thumbnailGeneration = UUID()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 3) {
                Button(action: onOpen) {
                    VStack(spacing: 3) {
                        thumbnailView
                        Text(item.displayName)
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                            .frame(width: 48)
                    }
                }
                .buttonStyle(.plain)
                Button("Sposta") { manager.moveItem = item }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.cyan)
                    .disabled(manager.busyIDs.contains(item.id))
            }

            if manager.busyIDs.contains(item.id) {
                ProgressView().controlSize(.mini).padding(2)
            } else if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        // Drag-out: rilascio fuori dalle finestre dell'app rimuove l'item dalla shelf
        .onDrag {
            guard let url = item.resolvedURL() else { return NSItemProvider() }
            dragSession.begin(url: url, onDropOutside: onRemove)
            return NSItemProvider(object: url as NSURL)
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.16), value: isHovered)
        .onAppear { loadThumbnail() }
        .onDisappear {
            if let thumbnailRequest { QLThumbnailGenerator.shared.cancel(thumbnailRequest) }
            thumbnailRequest = nil
            thumbnailGeneration = UUID()
        }
        .onChange(of: item.path) { _, _ in loadThumbnail() }
        .contextMenu {
            Button("Sposta in Documenti…") { manager.moveItem = item }
                .disabled(manager.busyIDs.contains(item.id))
            Button("Rinomina…") { manager.beginRename(item) }
                .disabled(manager.busyIDs.contains(item.id))
            Button("Copia percorso") { manager.copyPath(item) }
            Button("Comprimi in ZIP") { manager.compress(item) }
                .disabled(manager.busyIDs.contains(item.id))
            Menu("Ridimensiona immagine · copia PNG") {
                ForEach([512, 1024, 1920], id: \.self) { size in
                    Button("Lato massimo \(size) px") { manager.resize(item, maxSide: size) }
                }
            }.disabled(manager.busyIDs.contains(item.id) || !(UTType(filenameExtension: URL(fileURLWithPath: item.path).pathExtension)?.conforms(to: .image) ?? false))
            Divider()
            Button("Mostra nel Finder") {
                guard let url = item.resolvedURL() else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Rimuovi", role: .destructive) { onRemove() }
        }
    }

    // MARK: - Thumbnail

    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: 48, height: 48)

            if let thumb = thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }

    private func loadThumbnail() {
        if let thumbnailRequest { QLThumbnailGenerator.shared.cancel(thumbnailRequest) }
        let generation = UUID()
        thumbnailGeneration = generation
        thumbnail = nil
        guard let url = item.resolvedURL() else {
            thumbnail = NSWorkspace.shared.icon(forFile: item.path)
            return
        }
        let req = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 96, height: 96),
            scale: 2,
            representationTypes: .thumbnail
        )
        thumbnailRequest = req
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { thumb, _ in
            DispatchQueue.main.async {
                guard thumbnailGeneration == generation else { return }
                thumbnailRequest = nil
                thumbnail = thumb?.nsImage ?? NSWorkspace.shared.icon(forFile: url.path)
            }
        }
    }
}
