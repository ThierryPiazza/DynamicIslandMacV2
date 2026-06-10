import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var monitor: NowPlayingMonitor

    var body: some View {
        HStack(spacing: 12) {
            artworkView
            VStack(alignment: .leading, spacing: 4) {
                trackInfo
                progressBar
                controls
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Artwork

    private var artworkView: some View {
        Button {
            monitor.openSourceApp()
        } label: {
            Group {
                if let img = monitor.info.artwork {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(Color.white.opacity(0.08).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
            .overlay(
                // Indicatore visivo sottile: overlay scuro al hover
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(artworkHovered ? 0.22 : 0))
            )
            .onHover { over in
                withAnimation(.easeInOut(duration: 0.16)) { artworkHovered = over }
                if over { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .buttonStyle(.plain)
        .help("Apri \(monitor.info.source.isEmpty ? "il player" : monitor.info.source)")
    }

    @State private var artworkHovered = false

    // MARK: - Track info

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            if monitor.info.title.isEmpty {
                Text("Nessuna riproduzione")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                MarqueeText(
                    text: monitor.info.title,
                    font: .system(size: 12, weight: .semibold),
                    color: .white
                )
                .frame(height: 16)
            }

            HStack(spacing: 4) {
                if !monitor.info.artist.isEmpty {
                    MarqueeText(
                        text: monitor.info.artist,
                        font: .system(size: 11),
                        color: .white.opacity(0.55),
                        speed: 25
                    )
                    .frame(height: 14)
                }
                if !monitor.info.source.isEmpty {
                    Text("· \(monitor.info.source)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        // TimelineView fa avanzare la barra ogni secondo invece che a scatti
        // a ogni poll; da fermo lo schedule è praticamente inerte (il cambio
        // arriva col re-render quando isPlaying cambia).
        TimelineView(.periodic(from: .now, by: monitor.info.isPlaying ? 1 : 3600)) { _ in
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14)).frame(height: 4)
                    let progress = monitor.info.duration > 0
                        ? min(1, max(0, CGFloat(monitor.info.liveElapsed() / monitor.info.duration)))
                        : 0
                    Capsule()
                        .fill(Color.white.opacity(0.76))
                        .frame(width: geo.size.width * progress, height: 4)
                }
            }
        }
        .frame(height: 4)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 18) {
            controlButton(systemName: "backward.fill")  { monitor.prevTrack() }
            controlButton(systemName: monitor.info.isPlaying ? "pause.fill" : "play.fill", size: 15) {
                monitor.togglePlayPause()
            }
            controlButton(systemName: "forward.fill")   { monitor.nextTrack() }
        }
    }

    private func controlButton(systemName: String, size: CGFloat = 12, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

