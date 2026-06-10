import SwiftUI
import AppKit

/// Testo scorrevole senza GeometryReader annidati — misura via NSString per evitare layout loop.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 12, weight: .semibold)
    var nsFont: NSFont = .systemFont(ofSize: 12, weight: .semibold)
    var color: Color = .white
    var speed: Double = 30
    var pauseDuration: Double = 1.5

    @State private var offset: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var animationID: UUID = UUID()

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(font)
                .foregroundColor(color)
                .fixedSize()
                .offset(x: offset)
                .clipped()
                .frame(maxWidth: geo.size.width, alignment: .leading)
                .onAppear {
                    containerWidth = geo.size.width
                    restart()
                }
                .onChange(of: text) { _ in
                    offset = 0
                    animationID = UUID()
                    containerWidth = geo.size.width
                    restart()
                }
        }
    }

    private func measuredTextWidth() -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: nsFont]
        return (text as NSString).size(withAttributes: attrs).width
    }

    private func restart() {
        let tw = measuredTextWidth()
        guard tw > containerWidth + 4 else { return }
        let travel   = tw - containerWidth + 16
        let duration = travel / speed
        let id       = animationID

        DispatchQueue.main.asyncAfter(deadline: .now() + pauseDuration) {
            guard animationID == id else { return }
            withAnimation(.linear(duration: duration)) { offset = -travel }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + pauseDuration) {
                guard animationID == id else { return }
                offset = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    guard animationID == id else { return }
                    restart()
                }
            }
        }
    }
}
