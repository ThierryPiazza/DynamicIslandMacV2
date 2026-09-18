import SwiftUI

struct ClipboardView: View {
    @ObservedObject var monitor: ClipboardMonitor
    let notchState: NotchState
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var favoritesOnly = false

    var body: some View {
        let visibleItems = monitor.filtered(query: query, favoritesOnly: favoritesOnly)
        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                TextField("Cerca nella clipboard…", text: $query).textFieldStyle(.plain).focused($searchFocused)
                Button { favoritesOnly.toggle() } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                }.buttonStyle(.plain).help("Mostra solo preferiti")
                Menu {
                    Button("Svuota recenti (conserva preferiti)") { monitor.clear() }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28, height: 24)
                .fixedSize()
                .help("I recenti si cancellano a fine giornata. I preferiti vengono conservati.")
                .accessibilityLabel("Azioni clipboard")
            }.font(.system(size: 11)).padding(.horizontal, 12).padding(.top, 4)
            if visibleItems.isEmpty {
                emptyState
            } else {
                itemsList(visibleItems)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: searchFocused) { _, focused in notchState.isEditingClipboard = focused }
        .onDisappear { notchState.isEditingClipboard = false }
        .alert("Clipboard", isPresented: Binding(get: { monitor.message != nil }, set: { if !$0 { monitor.message = nil } })) {
            Button("OK") { monitor.message = nil }
        } message: { Text(monitor.message ?? "") }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "clipboard")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.3))
            Text(favoritesOnly ? "Nessun preferito trovato" : (query.isEmpty ? "Nessun elemento copiato" : "Nessun risultato"))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    private func itemsList(_ items: [ClipboardItem]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(items) { item in
                    HStack(spacing: 4) {
                        ClipboardRowView(item: item) { monitor.copy(item) }
                        Button { monitor.toggleFavorite(item) } label: {
                            Image(systemName: item.isFavorite ? "star.fill" : "star")
                                .foregroundStyle(item.isFavorite ? .yellow : .white.opacity(0.4))
                        }.buttonStyle(.plain).help(item.isFavorite ? "Rimuovi dai preferiti" : "Salva nei preferiti")
                    }.contextMenu {
                        Button("Copia") { monitor.copy(item) }
                        Button(item.isFavorite ? "Rimuovi dai preferiti" : "Salva nei preferiti") { monitor.toggleFavorite(item) }
                        Button("Elimina", role: .destructive) { monitor.remove(item) }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Row

struct ClipboardRowView: View {
    let item: ClipboardItem
    let onTap: () -> Void
    @State private var copied = false

    var body: some View {
        Button(action: {
            onTap()
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        }) {
            HStack(spacing: 8) {
                icon
                    .frame(width: 16)

                contentPreview
                    .frame(maxWidth: .infinity, alignment: .leading)

                if copied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green)
                        .transition(.scale.combined(with: .opacity))
                }

                Text(item.date, style: .time)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.07).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: copied)
    }

    private var icon: some View {
        Group {
            switch item.content {
            case .text:
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
            case .image:
                Image(systemName: "photo")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.content {
        case .text(let s):
            Text(s)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
        case .image(let thumbnail, _, _):
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }
}
