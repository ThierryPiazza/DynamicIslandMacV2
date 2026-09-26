import AppKit
import Combine

@MainActor
class WindowManager {
    private var panel: NotchPanel?
    let notchState        = NotchState()
    let nowPlayingMonitor = NowPlayingMonitor()
    let shelf             = ShelfManager.shared
    let clipboard         = ClipboardMonitor()
    let notes = NotesStore()
    lazy var activities = CompactActivityController(shelf: shelf)

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
    private var swipeVerticalAccumulated: CGFloat = 0
    private enum SwipeAxis { case horizontal, vertical }
    private var swipeAxis: SwipeAxis?

    deinit {
        hotkeyCollapseTask?.cancel()
        [mouseMoveGlobalMonitor, mouseMoveLocalMonitor, scrollMonitor]
            .compactMap { $0 }.forEach(NSEvent.removeMonitor)
    }

    func show() {
        guard let geometry = NotchGeometry.detectPreferred() else { return }
        notchState.updateGeometry(geometry)

        let p = NotchPanel(geometry: geometry, notchState: notchState,
                           nowPlaying: nowPlayingMonitor, shelf: shelf, clipboard: clipboard,
                           notes: notes, activities: activities)
        p.orderFrontRegardless()
        panel = p

        // Il panel non viene mai ridimensionato all'apertura/chiusura: resta alla
        // dimensione espansa e SwiftUI anima la forma nera al suo interno.
        setupDragProximity()
        observeScreenChanges()
        setupCompactSwipe()
        observeAppActivation()
        setupHitboxTracking()
        FileBrowserModel.shared.$choosingFolder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] choosing in
                self?.notchState.isFileDialogActive = choosing
            }.store(in: &cancellables)
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
                if self.settings.showsCompactActivity(musicPlaying: self.nowPlayingMonitor.info.isActivelyPlaying) {
                    self.activities.openCurrent(in: self.notchState)
                } else { self.notchState.expand() }
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
        notchState.$isChoosingShelfDestination
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMouseInteractivity() }
            .store(in: &cancellables)
        updateMouseInteractivity()
    }

    private func updateMouseInteractivity() {
        guard let p = panel else { return }
        // File access can trigger macOS permission dialogs; never cover them with a screen-saver-level window.
        if !notchState.isDragging {
            p.level = notchState.displayState == .expanded(tab: .files) ? .floating : .screenSaver
        }

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
        dragProximity.targetFrame = { [weak self] in self?.panel?.frame }
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

        if event.phase.contains(.began) { resetSwipe() }

        let state = notchState.displayState
        if state == .compact, settings.showsCompactActivity(musicPlaying: nowPlayingMonitor.info.isActivelyPlaying), activities.current != nil {
            resetSwipe()
            return
        }

        // Gestures attive solo in compact o expanded; ignora HUD
        guard state == .compact || state.isExpanded else {
            resetSwipe(); return
        }

        // Il cursore deve essere nella zona attiva. Il panel è sempre alla dimensione
        // espansa, quindi in compact NON basta "dentro il frame": serve la fascia del notch.
        let mouse = NSEvent.mouseLocation
        if case .compact = state {
            if let screen = NSScreen.main {
                let notchBottom = screen.frame.maxY - (screen.safeAreaInsets.top + 20)
                guard mouse.y >= notchBottom else {
                    resetSwipe(); return
                }
            }
        } else if let p = panel, !p.frame.contains(mouse) {
            resetSwipe(); return
        }

        // Fine gesto → reset
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            resetSwipe(); return
        }

        guard !swipeFired else { return }
        swipeAccumulated += event.scrollingDeltaX
        swipeVerticalAccumulated += event.scrollingDeltaY

        // Blocca l’asse per l’intero gesto: lo scroll verticale di testo e file non
        // deve diventare un cambio tab per una piccola deriva laterale.
        if swipeAxis == nil {
            let horizontal = abs(swipeAccumulated)
            let vertical = abs(swipeVerticalAccumulated)
            if horizontal >= 6, horizontal > vertical * 1.2 {
                swipeAxis = .horizontal
            } else if vertical >= 6, vertical > horizontal * 1.2 {
                swipeAxis = .vertical
            }
        }
        guard swipeAxis == .horizontal else { return }

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

    private func resetSwipe() {
        swipeAccumulated = 0
        swipeVerticalAccumulated = 0
        swipeAxis = nil
        swipeFired = false
    }

    private func observeScreenChanges() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.repositionPanel() }
            .store(in: &cancellables)
    }

    // MARK: - Auto-collapse quando un'altra app diventa attiva

    private func observeAppActivation() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
                if let state = self?.notchState, state.displayState == .expanded(tab: .files),
                   state.isFileDialogActive { return }
                self?.notchState.collapse()
            }.store(in: &cancellables)
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
