import AppKit
import Combine
import MediaRemoteAdapter

/// Lettura di sistema opzionale. Un errore lascia disponibili i provider nativi/browser.
@MainActor
final class SystemMediaProvider: ObservableObject {
    static let shared = SystemMediaProvider()
    @Published private(set) var status = "Disattivato"
    var onChange: ((TrackInfo.Payload?) -> Void)?
    private let controller = MediaController()
    private var enabled = false
    private(set) var isChecking = false
    private var initialTimeout: DispatchWorkItem?
    private var subscriptions = Set<AnyCancellable>()
    private var currentBundleID: String?

    private init() {
        controller.onTrackInfoReceived = { [weak self] track in
            guard let self, self.enabled else { return }
            self.initialTimeout?.cancel()
            self.initialTimeout = nil
            self.isChecking = false
            let payload = track?.payload
            self.currentBundleID = payload?.bundleIdentifier
            self.status = payload?.title?.isEmpty == false ? "Lettura di sistema attiva" : "In attesa di riproduzione"
            self.onChange?(payload)
        }
        controller.onListenerTerminated = { [weak self] in self?.failed() }
        controller.onDecodingError = { [weak self] _, _ in self?.failed() }
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.stop() }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self, self.enabled else { return }
                self.controller.stopListening()
                self.start()
            }.store(in: &subscriptions)
    }

    func start() {
        guard !controller.isListening else { return }
        enabled = true
        isChecking = true
        status = "Verifica lettura di sistema…"
        initialTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in self?.failed() }
        initialTimeout = timeout
        controller.startListening()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
    }

    func stop() {
        enabled = false
        isChecking = false
        initialTimeout?.cancel()
        initialTimeout = nil
        controller.stopListening()
        currentBundleID = nil
        status = "Disattivato"
        onChange?(nil)
    }

    private func failed() {
        guard enabled else { return }
        isChecking = false
        initialTimeout?.cancel()
        initialTimeout = nil
        controller.stopListening()
        currentBundleID = nil
        status = "Lettura di sistema non disponibile — uso alternative"
        onChange?(nil)
    }

    @discardableResult
    func send(_ command: MediaRemoteBridge.Command, expectedBundleID: String) -> Bool {
        guard enabled, !expectedBundleID.isEmpty, currentBundleID == expectedBundleID else { return false }
        let name: String
        switch command {
        case .play: name = "play"
        case .pause: name = "pause"
        case .togglePlayPause: name = "toggle_play_pause"
        case .nextTrack: name = "next_track"
        case .prevTrack: name = "previous_track"
        }
        return controller.send(name, expectedBundleID: expectedBundleID)
    }
}
