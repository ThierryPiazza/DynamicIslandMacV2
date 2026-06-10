import AppKit
import Combine

class WindowManager {
    private var panel: NotchPanel?
    let notchState        = NotchState()
    let nowPlayingMonitor = NowPlayingMonitor()
    let shelf             = ShelfManager.shared
    let clipboard         = ClipboardMonitor()
    let calendar          = CalendarMonitor()
    let weather           = WeatherMonitor()

    private let dragProximity      = DragProximityMonitor()
    private let settings           = ModuleSettings.shared
    private let hotkey             = HotkeyManager()
    /// Auto-chiusura dell'island 5s dopo l'apertura via hotkey.
    private var hotkeyCollapseTask: DispatchWorkItem?

    // Monitor per togglare ignoresMouseEvents: il panel resta sempre alla dimensione
    // espansa, quindi in compact la zona trasparente sotto il notch catturerebbe i click
    // (e ruberebbe il focus all'app sottostante). Quando il mouse è fuori dalla striscia
    // attiva la finestra ignora del tutto gli eventi → la hitbox fantasma sparisce.
    private var mouseMoveGlobalMonitor: Any?
    private var mouseMoveLocalMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    // Monitor globale per swipe a due dita sul notch compatto
    private var scrollMonitor: Any?
    private var swipeAccumulated: CGFloat = 0
    private var swipeFired = false

    func show() {
        guard let geometry = NotchGeometry.detectPreferred() else { return }
        notchState.updateGeometry(geometry)

        let p = NotchPanel(geometry: geometry, notchState: notchState,
                           nowPlaying: nowPlayingMonitor, shelf: shelf, clipboard: clipboard,
                           calendar: calendar, weather: weather)
        p.orderFrontRegardless()
        panel = p

        // Il panel non viene mai ridimensionato all'apertura/chiusura: resta alla
        // dimensione espansa e SwiftUI anima la forma nera al suo interno.
        setupDragProximity()
        observeScreenChanges()
        setupCompactSwipe()
        observeAppActivation()
        setupHitboxTracking()
        setupHotkey()
        observeDisplayPreference()
    }

    // MARK: - Hotkey globale (⌃⌥Spazio)

    private func setupHotkey() {
        hotkey.onActivate = { [weak self] in
            guard let self else { return }
            self.hotkeyCollapseTask?.cancel()
            if self.notchState.displayState.isExpanded {
                self.notchState.collapse()
            } else {
                self.notchState.expand()
                // Richiudi da solo dopo 5s, ma solo se il mouse non è sopra
                // l'island (collapseIfNotHovered controlla la forma reale).
                let task = DispatchWorkItem { [weak self] in
                    self?.notchState.collapseIfNotHovered()
                }
                self.hotkeyCollapseTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: task)
            }
        }
        if settings.hotkeyEnabled { hotkey.register() }
        settings.$hotkeyEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                enabled ? self?.hotkey.register() : self?.hotkey.unregister()
            }
            .store(in: &cancellables)
    }

    // MARK: - Schermo preferito

    private func observeDisplayPreference() {
        settings.$preferredDisplayID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.repositionPanel() }
            .store(in: &cancellables)
    }

    // MARK: - Hitbox dinamica (ignoresMouseEvents)

    private func setupHitboxTracking() {
        // Global: eventi destinati ad altre app (mouse fuori dal nostro panel,
        // o panel in modalità ignoresMouseEvents). Local: eventi nel nostro panel.
        mouseMoveGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.updateMouseInteractivity()
        }
        mouseMoveLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.updateMouseInteractivity()
            return event
        }
        // Riallinea subito la hitbox quando lo stato cambia (expand/collapse),
        // senza attendere il prossimo movimento del mouse.
        notchState.$displayState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMouseInteractivity() }
            .store(in: &cancellables)
        updateMouseInteractivity()
    }

    private func updateMouseInteractivity() {
        guard let p = panel else { return }

        // Durante drag il panel deve ricevere tutti gli eventi (drop target).
        if notchState.isDragging {
            if p.ignoresMouseEvents { p.ignoresMouseEvents = false }
            return
        }

        // Expanded: interattiva solo la forma reale del notch (angoli inferiori
        // arrotondati); negli angoli trasparenti i click passano all'app sotto.
        if notchState.displayState.isExpanded {
            let inside = notchState.expandedHitShape(inScreenFrame: p.frame)
                .contains(NSEvent.mouseLocation)
            if p.ignoresMouseEvents == inside { p.ignoresMouseEvents = !inside }
            return
        }

        // Compact: interattiva solo la striscia del notch (in coordinate schermo).
        var strip = notchState.compactHitRect(inPanelBounds: CGRect(origin: .zero, size: p.frame.size))
        strip.origin.x += p.frame.minX
        strip.origin.y += p.frame.minY

        let inside = strip.contains(NSEvent.mouseLocation)
        if p.ignoresMouseEvents == inside {
            p.ignoresMouseEvents = !inside
        }
    }

    private func setupDragProximity() {
        dragProximity.isAlreadyExpanded = { [weak self] in
            self?.notchState.displayState.isExpanded ?? false
        }
        dragProximity.onDragNearNotch = { [weak self] in
            // Il drag manager di macOS cerca destinazioni solo in finestre SOTTO
            // kCGDraggingWindowLevel (500). Abbassiamo il livello temporaneamente
            // così il nostro panel viene trovato come drop target.
            self?.panel?.level = NSWindow.Level(rawValue: 200)
            // Il panel deve ricevere eventi per essere trovato come drop target
            self?.panel?.ignoresMouseEvents = false
            self?.notchState.isDragging = true
            self?.notchState.showDropZone()
        }
        dragProximity.onDragEnded = { [weak self] in
            self?.notchState.isDragging = false
            self?.notchState.collapseIfNotHovered()
            // Ripristina il livello originale dopo che performDragOperation è terminato
            self?.panel?.level = .screenSaver
            self?.updateMouseInteractivity()
        }
        dragProximity.start()
    }

    // MARK: - Two-finger swipe on compact notch

    private func setupCompactSwipe() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollEvent(event)
            return event   // propaga sempre l'evento
        }
    }

    private func handleScrollEvent(_ event: NSEvent) {
        // Solo gesti trackpad (phase settato); ignora mouse wheel fisico
        guard event.phase != [] else { return }

        let state = notchState.displayState

        // Gestures attive solo in compact o expanded; ignora HUD
        guard state == .compact || state.isExpanded else {
            swipeAccumulated = 0; swipeFired = false; return
        }

        // Il cursore deve essere nella zona attiva. Il panel è sempre alla dimensione
        // espansa, quindi in compact NON basta "dentro il frame": serve la fascia del notch.
        let mouse = NSEvent.mouseLocation
        if case .compact = state {
            if let screen = NSScreen.main {
                let notchBottom = screen.frame.maxY - (screen.safeAreaInsets.top + 20)
                guard mouse.y >= notchBottom else {
                    swipeAccumulated = 0; swipeFired = false; return
                }
            }
        } else if let p = panel, !p.frame.contains(mouse) {
            swipeAccumulated = 0; swipeFired = false; return
        }

        // Fine gesto → reset
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            swipeAccumulated = 0; swipeFired = false; return
        }

        swipeAccumulated += event.scrollingDeltaX

        guard !swipeFired else { return }

        let threshold: CGFloat = 35
        if swipeAccumulated > threshold {
            swipeFired = true
            DispatchQueue.main.async {
                if case .compact = self.notchState.displayState {
                    self.notchState.lastSwipe = .left
                    self.nowPlayingMonitor.prevTrack()
                } else {
                    self.notchState.switchToAdjacentTab(direction: .left)
                }
            }
        } else if swipeAccumulated < -threshold {
            swipeFired = true
            DispatchQueue.main.async {
                if case .compact = self.notchState.displayState {
                    self.notchState.lastSwipe = .right
                    self.nowPlayingMonitor.nextTrack()
                } else {
                    self.notchState.switchToAdjacentTab(direction: .right)
                }
            }
        }
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.repositionPanel()
        }
    }

    // MARK: - Auto-collapse quando un'altra app diventa attiva

    private func observeAppActivation() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            // Non collassare se è la nostra stessa app ad essere attivata
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return }

            // Collassa sempre quando l'utente passa ad un'altra app
            self.notchState.collapse()
        }
    }

    private func repositionPanel() {
        // detectPreferred rispetta lo schermo scelto nelle impostazioni; se quel display
        // viene scollegato fa fallback sul display integrato con notch o sul principale.
        guard let geometry = NotchGeometry.detectPreferred(), let p = panel else { return }
        notchState.updateGeometry(geometry)
        // Sposta il panel sullo schermo giusto e aggiorna la geometria
        p.setFrame(notchState.currentFrame(for: geometry), display: true)
    }
}
