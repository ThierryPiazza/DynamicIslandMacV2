import Combine
import Sparkle
import SwiftUI

/// One updater for the lifetime of the app, shared by the menu and settings.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    let controller: SPUStandardUpdaterController
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    private var started = false

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
    }

    func start() {
        guard !started else { return }
        started = true
        controller.startUpdater()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}

struct AppUpdateSettings: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Section("Aggiornamenti") {
            LabeledContent("Versione", value: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            Toggle("Cerca aggiornamenti automaticamente", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.setAutomaticChecks($0) }))
            Button("Controlla aggiornamenti…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
            Text("Quando è disponibile una nuova versione, puoi scaricarla e installarla direttamente dall’app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
