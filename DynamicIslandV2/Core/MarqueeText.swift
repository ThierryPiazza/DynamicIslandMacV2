import SwiftUI
import AppKit

/// One cancellable animation task, scoped to the visible view and its layout.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 12, weight: .semibold)
    var nsFont: NSFont = .systemFont(ofSize: 12, weight: .semibold)
    var color: Color = .white
    var speed: Double = 30
    var pauseDuration: Double = 1.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0

    private struct AnimationKey: Equatable {
        let text: String
        let width: CGFloat
        let fontName: String
        let fontSize: CGFloat
        let reduceMotion: Bool
        let speed: Double
    }

    var body: some View {
        GeometryReader { geometry in
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .fixedSize()
                .offset(x: offset)
                .frame(width: geometry.size.width, alignment: .leading)
                .clipped()
                .task(id: AnimationKey(text: text, width: geometry.size.width,
                                       fontName: nsFont.fontName, fontSize: nsFont.pointSize,
                                       reduceMotion: reduceMotion, speed: speed)) {
                    offset = 0
                    let width = (text as NSString).size(withAttributes: [.font: nsFont]).width
                    guard !reduceMotion, geometry.size.width > 0, width > geometry.size.width + 4 else { return }
                    let travel = width - geometry.size.width + 16
                    let duration = travel / max(1, speed)
                    do {
                        while !Task.isCancelled {
                            try await Task.sleep(for: .seconds(max(0, pauseDuration)))
                            withAnimation(.linear(duration: duration)) { offset = -travel }
                            try await Task.sleep(for: .seconds(duration + max(0, pauseDuration)))
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) { offset = 0 }
                        }
                    } catch { /* View disappeared or text/layout changed. */ }
                }
        }
        .accessibilityLabel(text)
    }
}
