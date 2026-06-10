import SwiftUI
import QuickLookThumbnailing

struct ShelfView: View {
    @ObservedObject var manager: ShelfManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(manager.items) { item in
                    ShelfItemView(item: item,
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
    let onOpen:   () -> Void
    let onRemove: () -> Void

    @State private var thumbnail: NSImage? = nil
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
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

            if isHovered {
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
            _ = url.startAccessingSecurityScopedResource()

            var monitor: Any?
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
                if let m = monitor { NSEvent.removeMonitor(m) }
                monitor = nil
                let loc = NSEvent.mouseLocation
                let droppedOutside = !NSApp.windows.contains { $0.isVisible && $0.frame.contains(loc) }
                if droppedOutside { DispatchQueue.main.async { onRemove() } }
            }
            return NSItemProvider(object: url as NSURL)
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.16), value: isHovered)
        .onAppear { loadThumbnail() }
        .onChange(of: item.id) { _, _ in loadThumbnail() }
        .contextMenu {
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
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { thumb, _ in
            DispatchQueue.main.async {
                thumbnail = thumb?.nsImage ?? NSWorkspace.shared.icon(forFile: url.path)
            }
        }
    }
}
