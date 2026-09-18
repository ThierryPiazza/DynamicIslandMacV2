import AppKit
import Combine

enum ExpandedTab: Int, CaseIterable {
    // ID persistenti: Timer mantiene il vecchio valore anche rimuovendo due tab.
    case nowPlaying = 0
    case shelf = 1
    case clipboard = 2
    case notes = 3
    case timer = 5

    var icon: String {
        switch self {
        case .nowPlaying: return "music.note"
        case .shelf: return "tray"
        case .clipboard: return "clipboard"
        case .notes: return "note.text"
        case .timer: return "timer"
        }
    }

    var title: String {
        switch self {
        case .nowPlaying: return "Now Playing"
        case .shelf: return "Shelf"
        case .clipboard: return "Clipboard"
        case .notes: return "Appunti"
        case .timer: return "Timer"
        }
    }
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
    private let settings: ModuleSettings
    init(settings: ModuleSettings = .shared) { self.settings = settings }
    var isEditingClipboard = false
    var isPresentingShelfAction = false
    @Published var isChoosingShelfDestination = false
    @Published var displayState: NotchDisplayState = .compact
    @Published var isDragging = false
    var isEditingNotes = false
    @Published var lastSwipe: SwipeDirection? = nil

    @Published private(set) var geometry: NotchGeometry?

    private let expandedPaddingH: CGFloat      = 72
    private let expandedPaddingBottom: CGFloat = 148

    private let destinationExtraHeight: CGFloat = 180

    var expandedContentHeight: CGFloat {
        expandedPaddingBottom + (displayState == .expanded(tab: .shelf) && isChoosingShelfDestination ? destinationExtraHeight : 0)
    }

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
        var maximum = frame(for: .expanded(tab: .nowPlaying), geo: geo)
        maximum.origin.y -= destinationExtraHeight
        maximum.size.height += destinationExtraHeight
        return maximum
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
        let target = tab ?? settings.lastTab
        displayState = .expanded(tab: target)
    }

    func showDropZone() {
        displayState = .expanded(tab: .shelf)
    }

    func collapseIfNotHovered() {
        guard case .expanded = displayState, let geo = geometry else { return }
        if displayState == .expanded(tab: .notes), isEditingNotes { return }
        if displayState == .expanded(tab: .clipboard), isEditingClipboard { return }
        if displayState == .expanded(tab: .shelf), isPresentingShelfAction { return }
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
        let height = (geometry?.frame.height ?? 32) + expandedContentHeight
        let visibleFrame = CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
        return notchShape(in: visibleFrame, bottomRadius: 24)
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
        settings.lastTab = tab
    }

    /// Sposta al tab successivo o precedente ciclicamente.
    func switchToAdjacentTab(direction: SwipeDirection) {
        guard case .expanded(let current) = displayState else { return }
        let all = settings.visibleTabs
        guard !all.isEmpty else { return }
        guard let idx = all.firstIndex(of: current) else { switchTab(all[0]); return }
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
        case .expanded(let tab):
            let bottom = expandedPaddingBottom + (tab == .shelf && isChoosingShelfDestination ? destinationExtraHeight : 0)
            return CGRect(
                x: geo.frame.minX - expandedPaddingH,
                y: geo.frame.minY - bottom,
                width: geo.frame.width + expandedPaddingH * 2,
                height: geo.frame.height + bottom
            )
        }
    }
}
