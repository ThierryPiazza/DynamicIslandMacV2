import AppKit
import Combine

enum ExpandedTab: Int, CaseIterable {
    // ID persistenti: Timer mantiene il vecchio valore anche rimuovendo due tab.
    case nowPlaying = 0
    case shelf = 1
    case clipboard = 2
    case notes = 3
    case timer = 5
    case files = 7
    case stats = 8

    var icon: String {
        switch self {
        case .nowPlaying: return "music.note"
        case .shelf: return "tray"
        case .clipboard: return "clipboard"
        case .notes: return "note.text"
        case .timer: return "timer"
        case .files: return "folder"
        case .stats: return "chart.xyaxis.line"
        }
    }

    var title: String {
        switch self {
        case .nowPlaying: return "Now Playing"
        case .shelf: return "Shelf"
        case .clipboard: return "Clipboard"
        case .notes: return "Appunti"
        case .timer: return "Timer"
        case .files: return "File"
        case .stats: return "Stats"
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
    var isFileDialogActive = false
    var isEditingClipboard = false
    var isPresentingShelfAction = false
    @Published var isChoosingShelfDestination = false
    @Published var isShowingShelfActions = false
    @Published var displayState: NotchDisplayState = .compact
    @Published var isDragging = false
    var isEditingNotes = false
    var isPresentingNotesPopover = false
    @Published var lastSwipe: SwipeDirection? = nil

    @Published private(set) var geometry: NotchGeometry?

    private let expandedPaddingH: CGFloat      = 72
    private let expandedPaddingBottom: CGFloat = 148

    private let destinationExtraHeight: CGFloat = 180

    var expandedContentHeight: CGFloat {
        expandedPaddingBottom + (displayState == .expanded(tab: .files) || (displayState == .expanded(tab: .shelf) && (isChoosingShelfDestination || isShowingShelfActions)) ? destinationExtraHeight : 0)
    }

    /// Estensione orizzontale (sinistra + destra) del frame compatto.
    /// Crea lo spazio per i pill art/bars ai lati del notch hardware e per l'overflow
    /// dello scaleEffect hover. DEVE coincidere con NotchView.compactPaddingH.
    static let compactPaddingH:   CGFloat = 42
    /// Bordo visibile sotto il notch hardware, compresa la barra di progresso.
    static let compactVisibleExtension: CGFloat = 5
    /// Include il bordo visibile e lo spazio per lo zoom al passaggio del mouse.
    static let compactBelowNotch: CGFloat = compactVisibleExtension + 4


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

    /// Geometria pubblicata dalla stessa view che disegna l'isola compatta.
    @Published var compactInteractionRect: CGRect = .zero
    var compactInteractionRadius: CGFloat = 8

    func compactHitRect(inPanelBounds b: CGRect) -> CGRect {
        let rect = compactInteractionRect.isEmpty
            ? CGRect(x: -(geometry?.frame.width ?? 200) / 2, y: 0,
                     width: geometry?.frame.width ?? 200, height: geometry?.frame.height ?? 32)
            : compactInteractionRect
        return CGRect(x: b.midX + rect.minX, y: b.maxY - rect.maxY,
                      width: rect.width, height: rect.height)
    }

    /// Unica sagoma per hover, click, scroll e passaggio degli eventi alla finestra sotto.
    func interactionShape(in bounds: CGRect) -> CGPath {
        if displayState.isExpanded { return expandedHitShape(inScreenFrame: bounds) }
        return notchShape(in: compactHitRect(inPanelBounds: bounds), bottomRadius: compactInteractionRadius)
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
        // Il popover si estende fuori dall'island e include controlli senza focus di testo.
        if displayState == .expanded(tab: .notes), isPresentingNotesPopover { return }
        // Il mouse può uscire dall'island mentre il campo conserva il focus.
        // NSTextView include anche il field editor dei TextField SwiftUI.
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
           editor.isEditable { return }
        // Only suspend auto-close while macOS may be presenting an access dialog.
        if displayState == .expanded(tab: .files), isFileDialogActive { return }
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
            let bottom = expandedPaddingBottom + (tab == .files || (tab == .shelf && (isChoosingShelfDestination || isShowingShelfActions)) ? destinationExtraHeight : 0)
            return CGRect(
                x: geo.frame.minX - expandedPaddingH,
                y: geo.frame.minY - bottom,
                width: geo.frame.width + expandedPaddingH * 2,
                height: geo.frame.height + bottom
            )
        }
    }
}
