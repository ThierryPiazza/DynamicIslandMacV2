import SwiftUI

private enum NotchDesign {
    static let compactRadius: CGFloat = 13
    static let expandedRadius: CGFloat = 24
    static let miniArtworkRadius: CGFloat = 7
    static let tabRadius: CGFloat = 8
    static let progressLineWidth: CGFloat = 2.2

    static let hoverSpring = Animation.interpolatingSpring(mass: 1.0, stiffness: 560, damping: 44)
    static let morphSpring = Animation.interpolatingSpring(mass: 1.0, stiffness: 390, damping: 38)
    static let contentSpring = Animation.interpolatingSpring(mass: 1.0, stiffness: 420, damping: 36)
    static let quickSpring = Animation.interpolatingSpring(mass: 1.0, stiffness: 700, damping: 48)
    static let fade = Animation.easeInOut(duration: 0.18)
}

struct NotchView: View {
    let geometry: NotchGeometry
    @ObservedObject var notchState: NotchState
    @ObservedObject var nowPlaying: NowPlayingMonitor
    let shelf: ShelfManager
    let clipboard: ClipboardMonitor
    @ObservedObject var calendar: CalendarMonitor
    @ObservedObject var weather: WeatherMonitor
    @ObservedObject private var settings = ModuleSettings.shared

    // Hover sopra il notch chiuso
    @State private var isHovering = false
    // Bounce offset per feedback swipe canzone
    @State private var bounceOffset: CGFloat = 0
    // Task per apertura ritardata in hover mode
    @State private var hoverOpenTask: DispatchWorkItem? = nil
    // Peek al cambio brano: il notch compatto raddoppia in altezza e mostra
    // il titolo del brano appena partito tra cover e wave.
    @State private var peekTitle: String? = nil
    @State private var peekTask: DispatchWorkItem? = nil

    /// Deve coincidere con il valore in NotchState.
    private let compactPaddingH: CGFloat = NotchState.compactPaddingH

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {

                // ── FORMA NERA UNIFICATA ────────────────────────────────────────────
                // Un'unica shape che morpha tra compact ed expanded con una sola spring:
                // il panel non viene mai ridimensionato, quindi niente scatti del frame
                // né swap di view durante l'apertura/chiusura.
                islandShape(proxySize: proxy.size)

                // ── CONTENUTO ESPANSO / HUD ──────────────────────────────────────────
                VStack(spacing: 0) {
                    Spacer().frame(height: geometry.frame.height)
                    expandedContentView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            // Click: apre in modalità click e mix
            .onTapGesture {
                guard settings.openOnClick else { return }
                if case .compact = notchState.displayState { notchState.expand() }
            }
            .background(
                DropHoverView(
                    onEnter: {
                        // Deferiamo al ciclo successivo per evitare mutazioni @State
                        // mentre SwiftUI sta ancora processando un aggiornamento pubblicato.
                        DispatchQueue.main.async {
                            withAnimation(NotchDesign.hoverSpring) { isHovering = true }
                            scheduleHoverOpen()
                        }
                    },
                    onExit: {
                        DispatchQueue.main.async {
                            withAnimation(NotchDesign.hoverSpring) { isHovering = false }
                            hoverOpenTask?.cancel()
                            hoverOpenTask = nil
                            notchState.collapseIfNotHovered()
                        }
                    },
                    isDragOver: .constant(false),
                    isActiveAt: { point, bounds in
                        // In expanded tutto il panel è zona attiva; in compact solo
                        // la striscia del notch (il panel resta a dimensione massima).
                        if notchState.displayState.isExpanded { return true }
                        return notchState.compactHitRect(inPanelBounds: bounds).contains(point)
                    }
                )
            )
        }
        // ignoresSafeArea DEVE stare fuori dal GeometryReader: se è dentro, il GeometryReader
        // riporta comunque dimensioni ridotte del safe area e il layout viene spinto in basso.
        // Posizionato qui, annulla completamente gli inset che macOS aggiunge all'NSHostingView
        // per la zona menu bar, così y=0 del panel corrisponde davvero alla cima dello schermo.
        .ignoresSafeArea(.all)
        .opacity(settings.notchOpacity)
        .animation(NotchDesign.fade, value: settings.notchOpacity)
        // Spring critico Apple-style: nessun overshoot, sensazione "pesante e precisa"
        .animation(NotchDesign.morphSpring, value: notchState.displayState)
        .onChange(of: nowPlaying.info.title) { newTitle in
            // Peek solo in compact, con un brano reale in riproduzione.
            guard !newTitle.isEmpty,
                  nowPlaying.info.isPlaying,
                  !notchState.displayState.isExpanded else { return }
            DispatchQueue.main.async {
                peekTask?.cancel()
                withAnimation(NotchDesign.morphSpring) { peekTitle = newTitle }
                let task = DispatchWorkItem {
                    withAnimation(NotchDesign.morphSpring) { peekTitle = nil }
                }
                peekTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: task)
            }
        }
        .onChange(of: notchState.lastSwipe) { direction in
            guard let dir = direction else { return }

            // Swipe in hover/mix mode: cancella il timer e lo riavvia (non aprire mentre si swipa)
            if settings.openOnHover && isHovering {
                // Async per evitare "Publishing changes from within view updates"
                DispatchQueue.main.async {
                    hoverOpenTask?.cancel()
                    hoverOpenTask = nil
                    scheduleHoverOpen()
                }
            }

            let dx: CGFloat = dir == .right ? -20 : 20
            withAnimation(.interpolatingSpring(mass: 1.0, stiffness: 760, damping: 34)) { bounceOffset = dx }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(NotchDesign.quickSpring) { bounceOffset = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                notchState.lastSwipe = nil
            }
        }
    }

    // MARK: - Hover open helper

    private func scheduleHoverOpen() {
        guard settings.openOnHover, case .compact = notchState.displayState else { return }
        hoverOpenTask?.cancel()
        let delay = settings.hoverDelay
        // Differisce la creazione del task al ciclo successivo per evitare
        // "Publishing changes from within view updates" quando le impostazioni cambiano.
        DispatchQueue.main.async {
            let task = DispatchWorkItem { notchState.expand() }
            hoverOpenTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
        }
    }

    // MARK: - Island shape (compact ↔ expanded)

    /// Unica forma nera per tutti gli stati. In compact copre il notch hardware
    /// (allungandosi per art+bars quando suona), in expanded riempie l'intero panel.
    /// Larghezza, altezza e raggio animano insieme con una sola spring → morph fluido.
    @ViewBuilder
    private func islandShape(proxySize: CGSize) -> some View {
        let expanded = notchState.displayState.isExpanded
        let playing = nowPlaying.info.isActivelyPlaying && !expanded
        let showSides = settings.compactSideViewsEnabled
        // Peek cambio brano: forma alta il doppio, pill + titolo nella fascia inferiore.
        let peeking = peekTitle != nil && playing && showSides
        let compactW: CGFloat = (playing && showSides)
            ? geometry.frame.width + compactPaddingH * 2
            : geometry.frame.width
        let shapeW: CGFloat = expanded ? proxySize.width  : compactW
        let compactH: CGFloat = geometry.frame.height * (peeking ? 2 : 1) + 1
        let shapeH: CGFloat = expanded ? proxySize.height : compactH
        let hoverScale = isHovering && !expanded

        ZStack {
            NotchShape(bottomRadius: expanded ? NotchDesign.expandedRadius : NotchDesign.compactRadius)
                .fill(Color.black)

            if playing && showSides {
                HStack(spacing: 0) {
                    compactArtPill
                        .padding(.leading, 9)
                    if peeking, let title = peekTitle {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 6)
                            .transition(.opacity)
                    } else {
                        Spacer()
                    }
                    compactBarsPill
                        .padding(.trailing, 9)
                }
                // Durante il peek la riga scende nella metà inferiore (sotto il
                // notch hardware), così cover, titolo e wave restano visibili.
                .frame(height: geometry.frame.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: peeking ? .bottom : .top)
                .animation(NotchDesign.morphSpring, value: peeking)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            }
        }
        .frame(width: shapeW, height: shapeH, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            if !expanded {
                NotchProgressIndicator(
                    nowPlaying: nowPlaying,
                    color: settings.accentColor,
                    bottomRadius: NotchDesign.compactRadius,
                    shapeWidth: shapeW,
                    shapeHeight: compactH
                )
                .allowsHitTesting(false)
            }
        }
        .offset(x: expanded ? 0 : bounceOffset, y: expanded ? 0 : -0.8)
        .scaleEffect(
            x: (hoverScale && !playing) ? 1.06 : 1.0,
            y: hoverScale ? 1.08 : 1.0,
            anchor: .top
        )
        .animation(NotchDesign.hoverSpring, value: isHovering)
        .animation(NotchDesign.morphSpring, value: shapeW)
        .animation(NotchDesign.morphSpring, value: shapeH)
    }

    // MARK: - Compact pills

    /// Miniatura della copertina su sfondo nero (22×22 pt, angoli 5 pt).
    private var compactArtPill: some View {
        ZStack {
            RoundedRectangle(cornerRadius: NotchDesign.miniArtworkRadius, style: .continuous).fill(Color.black)
            if let img = nowPlaying.info.artwork {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: NotchDesign.miniArtworkRadius, style: .continuous))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .frame(width: 22, height: 22)
    }

    /// Tre barre animate su sfondo nero a capsula.
    private var compactBarsPill: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                MusicBar(delay: Double(i) * 0.15, color: settings.accentColor)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(Capsule().fill(Color.black))
    }

    // MARK: - Content (expanded / HUD only)

    @ViewBuilder
    private var expandedContentView: some View {
        switch notchState.displayState {
        case .compact:
            EmptyView()

        case .expanded(let tab):
            VStack(spacing: 0) {
                if settings.showTabBar {
                    tabBar(active: tab)
                        .padding(.top, 6)
                }
                tabContent(tab: tab)
                    .id(tab)   // forza SwiftUI a ricreare la view al cambio tab → attiva la transition
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 8)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                        removal:   .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                    ))
                    .animation(NotchDesign.contentSpring, value: tab)
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                removal:   .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
            ))

        }
    }

    // MARK: - Tab bar

    @Namespace private var tabIndicatorNS

    private func tabBar(active: ExpandedTab) -> some View {
        HStack(spacing: 12) {
            tabButton(.nowPlaying, icon: "music.note",     active: active)
            tabButton(.shelf,      icon: "tray",           active: active)
            tabButton(.clipboard,  icon: "clipboard",      active: active)
            tabButton(.calendar,   icon: "calendar",       active: active)
            tabButton(.weather,    icon: "cloud.sun.fill", active: active)
        }
        .animation(NotchDesign.contentSpring, value: active)
    }

    private func tabButton(_ tab: ExpandedTab, icon: String, active: ExpandedTab) -> some View {
        let isActive = active == tab
        let accent = settings.accentColor
        return Button { notchState.switchTab(tab) } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? accent : .white.opacity(0.3))
                .frame(width: 26, height: 20)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: NotchDesign.tabRadius, style: .continuous)
                            .fill(accent.opacity(0.18))
                            .matchedGeometryEffect(id: "tabPill", in: tabIndicatorNS)
                    }
                }
                .animation(NotchDesign.contentSpring, value: isActive)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab content

    @ViewBuilder
    private func tabContent(tab: ExpandedTab) -> some View {
        switch tab {
        case .nowPlaying:
            NowPlayingView(monitor: nowPlaying)
        case .shelf:
            FileHubView(shelf: shelf, isDragging: notchState.isDragging)
        case .clipboard:
            ClipboardView(monitor: clipboard)
        case .calendar:
            CalendarView(monitor: calendar)
        case .weather:
            WeatherView(monitor: weather)
        }
    }

}

// MARK: - Music bar

struct MusicBar: View {
    let delay: Double
    var color: Color = .white
    @State private var height: CGFloat = 4

    var body: some View {
        Capsule()
            .fill(color.opacity(0.68))
            .frame(width: 3, height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.62).repeatForever(autoreverses: true).delay(delay)) {
                    height = [7, 13, 9].randomElement() ?? 10
                }
            }
    }
}

// MARK: - DropHoverView

/// NSViewRepresentable solo per hover — il drop è gestito da DropContainerView nel panel.
struct DropHoverView: NSViewRepresentable {
    var onEnter: () -> Void
    var onExit:  () -> Void
    @Binding var isDragOver: Bool
    /// Limita la zona di hover: la view copre l'intero panel (sempre a dimensione
    /// espansa), ma in compact solo la striscia del notch deve reagire.
    var isActiveAt: ((NSPoint, NSRect) -> Bool)? = nil

    func makeNSView(context: Context) -> DropHoverNSView {
        let v = DropHoverNSView()
        v.onEnter = onEnter
        v.onExit  = onExit
        v.isActiveAt = isActiveAt
        return v
    }

    func updateNSView(_ nsView: DropHoverNSView, context: Context) {
        nsView.onEnter = onEnter
        nsView.onExit  = onExit
        nsView.isActiveAt = isActiveAt
    }
}

class DropHoverNSView: NSView {
    var onEnter: (() -> Void)?
    var onExit:  (() -> Void)?
    var isActiveAt: ((NSPoint, NSRect) -> Bool)?
    private var trackingArea: NSTrackingArea?
    private var inside = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: opts, owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { evaluate(event) }
    override func mouseMoved(with event: NSEvent)   { evaluate(event) }
    override func mouseExited(with event: NSEvent)  { setInside(false) }

    private func evaluate(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        setInside(isActiveAt?(p, bounds) ?? true)
    }

    private func setInside(_ value: Bool) {
        guard value != inside else { return }
        inside = value
        value ? onEnter?() : onExit?()
    }
}

// MARK: - Notch perimeter progress indicator

/// Traccia i tre lati del notch (sinistra → basso → destra), riempita in base al progresso.
struct NotchPerimeterShape: Shape {
    let bottomRadius: CGFloat
    var verticalOffset: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = 2

        let minX = rect.minX + inset
        let maxX = rect.maxX - inset

        let topY = rect.minY
        let bottomY = rect.maxY + verticalOffset

        let r = max(0, min(bottomRadius, (bottomY - topY) / 2, (maxX - minX) / 2))

        var p = Path()

        p.move(to: CGPoint(x: minX, y: topY))

        p.addLine(to: CGPoint(x: minX, y: bottomY - r))

        p.addArc(
            tangent1End: CGPoint(x: minX, y: bottomY),
            tangent2End: CGPoint(x: minX + r, y: bottomY),
            radius: r
        )

        p.addLine(to: CGPoint(x: maxX - r, y: bottomY))

        p.addArc(
            tangent1End: CGPoint(x: maxX, y: bottomY),
            tangent2End: CGPoint(x: maxX, y: bottomY - r),
            radius: r
        )

        p.addLine(to: CGPoint(x: maxX, y: topY))

        return p
    }
}

struct NotchProgressIndicator: View {
    let nowPlaying: NowPlayingMonitor
    let color: Color
    let bottomRadius: CGFloat
    let shapeWidth: CGFloat
    let shapeHeight: CGFloat

    private let lineWidth: CGFloat = 2.5

    // Quanto la barra viene tenuta dentro lateralmente.
    // Aumenta se i lati sono ancora tagliati.
    private let horizontalInset: CGFloat = -1

    // Quanto abbassi solo la parte bassa della progress bar.
    // La partenza in alto rimane a y = 0.
    private let verticalDrop: CGFloat = 3

    var body: some View {
        // Tick a 0.5s solo mentre suona: da fermo lo schedule è praticamente
        // inerte (il parent ri-renderizza al cambio di stato e lo riattiva).
        TimelineView(.periodic(from: .now, by: nowPlaying.info.isActivelyPlaying ? 0.5 : 3600)) { _ in
            let info = nowPlaying.info
            let hasProgress = info.isActivelyPlaying && info.duration > 0
            let progress: CGFloat = hasProgress
                ? min(1, max(0, CGFloat(info.liveElapsed() / info.duration)))
                : 0

            NotchPerimeterShape(
                bottomRadius: bottomRadius,
                verticalOffset: verticalDrop
            )
            .trim(from: 0, to: progress)
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .shadow(color: color.opacity(0.65), radius: 3)
            .frame(
                width: shapeWidth - horizontalInset * 2,
                height: shapeHeight - lineWidth
            )
            .padding(.horizontal, horizontalInset)
            .padding(.top, lineWidth / 2)
            .opacity(hasProgress ? 1 : 0)
        }
        .frame(width: shapeWidth, height: shapeHeight, alignment: .top)
    }
}

// MARK: - NotchShape

/// Shape del notch con bordo superiore piatto e bordi inferiori arrotondati.
/// Il raggio è animabile: l'eventuale undershoot dello spring sotto zero
/// viene clampato in path(in:), quindi nessun flash a raggio 0.
struct NotchShape: Shape {
    /// Raggio degli angoli inferiori. Superiori sempre 0.
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Coordinate SwiftUI: y=0 in alto, y=rect.maxY in basso.
        // Bordo superiore (minY) piatto; bordi inferiori (maxY) arrotondati.
        let r = max(0, min(bottomRadius, rect.height / 2, rect.width / 2))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))          // top-left  (flat)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))        // top-right (flat)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))    // lato destro
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY),
                 radius: r)                                        // angolo bottom-right
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))   // bordo inferiore
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r),
                 radius: r)                                        // angolo bottom-left
        p.closeSubpath()
        return p
    }
}


// MARK: - File drop routing

extension Notification.Name {
    static let fileHubConvertDrop = Notification.Name("fileHub.convertDrop")
    static let fileHubBGDrop = Notification.Name("fileHub.bgDrop")
}

