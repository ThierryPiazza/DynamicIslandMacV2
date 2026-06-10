import AppKit
import Combine

enum ExpandedTab: CaseIterable {
    case nowPlaying
    case shelf
    case clipboard
    case calendar
    case weather
}

enum NotchDisplayState: Equatable {
    case compact
    case expanded(tab: ExpandedTab)

    var isExpanded: Bool {
        if case .expanded = self { return true }
        return false
    }

    static func == (lhs: NotchDisplayState, rhs: NotchDisplayState) -> Bool {
        switch (lhs, rhs) {
        case (.compact, .compact):                 return true
        case (.expanded(let a), .expanded(let b)): return a == b
        default:                                   return false
        }
    }
}

enum SwipeDirection { case left, right }

class NotchState: ObservableObject {
    @Published var displayState: NotchDisplayState = .compact
    @Published var isDragging = false
    @Published var lastSwipe: SwipeDirection? = nil

    private var geometry: NotchGeometry?

    private let expandedPaddingH: CGFloat      = 72
    private let expandedPaddingBottom: CGFloat = 148

    /// Estensione orizzontale (sinistra + destra) del frame compatto.
    /// Crea lo spazio per i pill art/bars ai lati del notch hardware e per l'overflow
    /// dello scaleEffect hover. DEVE coincidere con NotchView.compactPaddingH.
    static let compactPaddingH:   CGFloat = 42
    /// Estensione verso il basso: solo quel tanto che basta per non clippare lo zoom hover
    /// (geometry.frame.height × 0.06 ≈ 2–3 pt). Nessuna semisfera.
    static let compactBelowNotch: CGFloat = 5


    func updateGeometry(_ geo: NotchGeometry) { geometry = geo }

    /// Il panel resta SEMPRE alla dimensione espansa: l'apertura/chiusura anima solo
    /// la forma nera dentro SwiftUI, senza ridimensionare la NSWindow (che è la causa
    /// principale di scatti/lag). Le aree trasparenti sono escluse dall'hit testing.
    func currentFrame(for geo: NotchGeometry) -> CGRect {
        frame(for: .expanded(tab: .nowPlaying), geo: geo)
    }

    /// Zona interattiva del notch compatto, in coordinate del panel (AppKit, y verso l'alto):
    /// striscia centrata in alto larga quanto notch + pill laterali.
    func compactHitRect(inPanelBounds b: CGRect) -> CGRect {
        let w = (geometry?.frame.width  ?? 200) + Self.compactPaddingH * 2
        let h = (geometry?.frame.height ?? 32)  + Self.compactBelowNotch
        return CGRect(x: b.midX - w / 2, y: b.maxY - h, width: w, height: h)
    }

    // MARK: - Transitions

    func expand(tab: ExpandedTab? = nil) {
        guard case .compact = displayState else { return }
        let target = tab ?? ModuleSettings.shared.lastTab
        displayState = .expanded(tab: target)
    }

    func showDropZone() {
        displayState = .expanded(tab: .shelf)
    }

    func collapseIfNotHovered() {
        guard case .expanded = displayState, let geo = geometry else { return }
        let expandedFrame = frame(for: displayState, geo: geo)
        let mouse = NSEvent.mouseLocation
        // Controlla la forma reale del notch (arrotondata), non il semplice rettangolo:
        // il mouse negli angoli trasparenti NON conta come "dentro".
        guard !notchShape(in: expandedFrame, bottomRadius: 24).contains(mouse) else { return }
        displayState = .compact
    }

    /// Forma reale del notch espanso in coordinate schermo, per l'hit testing
    /// a livello finestra (gli angoli trasparenti non devono catturare eventi).
    func expandedHitShape(inScreenFrame frame: CGRect) -> CGPath {
        notchShape(in: frame, bottomRadius: 24)
    }

    /// Forma del notch in coordinate schermo: bordo superiore piatto, inferiore arrotondato.
    private func notchShape(in rect: CGRect, bottomRadius r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
        path.addArc(tangent1End: CGPoint(x: rect.maxX,     y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX - r,  y: rect.minY), radius: r)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.minX,     y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX,      y: rect.minY + r), radius: r)
        path.closeSubpath()
        return path
    }

    func collapse() {
        guard case .expanded = displayState else { return }
        displayState = .compact
    }

    func switchTab(_ tab: ExpandedTab) {
        displayState = .expanded(tab: tab)
        ModuleSettings.shared.lastTab = tab
    }

    /// Sposta al tab successivo o precedente ciclicamente.
    func switchToAdjacentTab(direction: SwipeDirection) {
        guard case .expanded(let current) = displayState else { return }
        let all = ExpandedTab.allCases
        guard let idx = all.firstIndex(of: current) else { return }
        let next: ExpandedTab
        if direction == .right {
            next = all[(idx + 1) % all.count]
        } else {
            next = all[(idx - 1 + all.count) % all.count]
        }
        switchTab(next)
    }

// MARK: - Frames

    private func frame(for state: NotchDisplayState, geo: NotchGeometry) -> CGRect {
        switch state {
        case .compact:
            // Il frame si estende di compactPaddingH a sinistra e a destra del notch hardware
            // (per i pill art/bars visibili ai lati) e di compactBelowNotch verso il basso
            // (per la semisfera hover). La forma nera in NotchView copre SOLO geo.frame,
            // quindi i bordi estesi sono trasparenti.
            let pH  = Self.compactPaddingH
            let ext = Self.compactBelowNotch
            return CGRect(
                x: geo.frame.minX  - pH,
                y: geo.frame.minY  - ext,
                width:  geo.frame.width  + pH * 2,
                height: geo.frame.height + ext
            )
        case .expanded:
            return CGRect(
                x: geo.frame.minX - expandedPaddingH,
                y: geo.frame.minY - expandedPaddingBottom,
                width: geo.frame.width + expandedPaddingH * 2,
                height: geo.frame.height + expandedPaddingBottom
            )
        }
    }
}
