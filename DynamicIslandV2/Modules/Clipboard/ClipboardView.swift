import SwiftUI

struct ClipboardView: View {
    @ObservedObject var monitor: ClipboardMonitor

    var body: some View {
        VStack(spacing: 0) {
            if monitor.items.isEmpty {
                emptyState
            } else {
                itemsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "clipboard")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.3))
            Text("Nessun elemento copiato")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    private var itemsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(monitor.items) { item in
                    ClipboardRowView(item: item) {
                        monitor.copy(item)
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
