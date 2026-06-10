import AppKit
import EventKit
import Combine

final class CalendarMonitor: NSObject, ObservableObject {
    @Published var events: [EKEvent] = []
    @Published var isAuthorized = false
    @Published var isNotDetermined = false

    private let store = EKEventStore()
    private var refreshTimer: Timer?
    /// Timer a breve intervallo usato dopo l'apertura di Impostazioni di Sistema:
    /// EventKit non invia notifiche quando l'utente concede l'accesso da lì,
    /// quindi poll ogni 2 secondi per massimo 60 secondi.
    private var authPoller: Timer?

    override init() {
        super.init()
        updateAuthStatus()
        NotificationCenter.default.addObserver(
            self, selector: #selector(storeChanged),
            name: .EKEventStoreChanged, object: store
        )
    }

    func updateAuthStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        isNotDetermined = (status == .notDetermined)
        if #available(macOS 14.0, *) {
            isAuthorized = (status == .fullAccess)
        } else {
            isAuthorized = (status == .authorized)
        }
        if isAuthorized {
            stopPollingAuthStatus()
            refresh()
        }
    }

    func requestAccess() {
        // Il panel è nonActivating → senza activate() il dialogo TCC
        // rimane nascosto dietro l'app in primo piano e l'utente non lo vede.
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            Task { @MainActor in
                _ = try? await store.requestFullAccessToEvents()
                updateAuthStatus()
                // Se ancora non autorizzato (utente ha rimandato a Impostazioni),
                // avvia il poller così rileva l'accesso concesso dall'esterno.
                if !isAuthorized { startPollingAuthStatus() }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] _, _ in
                DispatchQueue.main.async { self?.updateAuthStatus() }
            }
        }
    }

    /// Avvia un poller che controlla lo stato ogni 2 secondi per 60 secondi.
    /// Usato dopo che l'utente apre Impostazioni di Sistema per concedere accesso manualmente.
    func startPollingAuthStatus() {
        stopPollingAuthStatus()
        var elapsed = 0
        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            elapsed += 2
            self.updateAuthStatus()
            if self.isAuthorized || elapsed >= 60 { self.stopPollingAuthStatus() }
        }
        t.tolerance = 0.5
        authPoller = t
    }

    func stopPollingAuthStatus() {
        authPoller?.invalidate()
        authPoller = nil
    }

    func refresh() {
        guard isAuthorized else { return }
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: now) else { return }
        let pred = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        events = store.events(matching: pred)
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
            .map { $0 }

        refreshTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            self?.refresh()
        }
        t.tolerance = 30
        refreshTimer = t
    }

    @objc private func storeChanged() {
        DispatchQueue.main.async { self.refresh() }
    }
}
