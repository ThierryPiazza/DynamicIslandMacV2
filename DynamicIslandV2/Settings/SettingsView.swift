import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = ModuleSettings.shared
    @ObservedObject private var media = SystemMediaProvider.shared

    /// Display attualmente collegati: (id, nome). Ricalcolato a ogni render.
    private var availableDisplays: [(id: Int, name: String)] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? CGDirectDisplayID else { return nil }
            return (Int(id), screen.localizedName)
        }
    }

    var body: some View {
        Form {

            // ── Interazione ─────────────────────────────────────────────────
            Section("Interazione") {
                Picker("Apertura notch", selection: $settings.openModeIndex) {
                    Text("Click").tag(0)
                    Text("Hover").tag(1)
                    Text("Mix").tag(2)
                }
                .pickerStyle(.segmented)

                if settings.openOnHover {
                    HStack {
                        Text("Ritardo hover")
                        Spacer()
                        Slider(value: $settings.hoverDelay, in: 0.1...1.0, step: 0.1)
                            .frame(width: 140)
                        Text("\(Int(settings.hoverDelay * 1000)) ms")
                            .foregroundColor(.secondary)
                            .frame(width: 48, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
            }

            // ── Schermo ──────────────────────────────────────────────────────
            Section("Schermo") {
                Picker("Mostra il notch su", selection: $settings.preferredDisplayID) {
                    Text("Automatico").tag(0)
                    ForEach(availableDisplays, id: \.id) { display in
                        Text(display.name).tag(display.id)
                    }
                    // Display scelto in passato ma ora scollegato: mantieni la voce
                    // così la selezione non si azzera (riaggancia quando ricollegato).
                    if settings.preferredDisplayID != 0,
                       !availableDisplays.contains(where: { $0.id == settings.preferredDisplayID }) {
                        Text("Display scollegato").tag(settings.preferredDisplayID)
                    }
                }
                Text("Con \"Automatico\" il notch va sul display integrato; se il Mac è chiuso (clamshell) passa allo schermo principale.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // ── Vista ────────────────────────────────────────────────────────
            Section("Vista") {
                Toggle("Mostra barra tab quando aperto", isOn: $settings.showTabBar)
                Toggle("Viste laterali nel notch compatto", isOn: $settings.compactSideViewsEnabled)
                Toggle("Attività nel notch compatto", isOn: $settings.compactActivitiesEnabled)

                HStack {
                    Text("Trasparenza notch")
                    Spacer()
                    // Slider in punti percentuali interi: con 0.3...1.0 e step 0.05
                    // l'errore di virgola mobile impediva di raggiungere il 100%.
                    Slider(
                        value: Binding(
                            get: { (settings.notchOpacity * 100).rounded() },
                            set: { settings.notchOpacity = $0.rounded() / 100 }
                        ),
                        in: 30...100, step: 5
                    )
                    .frame(width: 140)
                    Text("\(Int((settings.notchOpacity * 100).rounded()))%")
                        .foregroundColor(.secondary)
                        .frame(width: 38, alignment: .trailing)
                        .monospacedDigit()
                }

                Picker("Tab di default", selection: $settings.defaultTabIndex) {
                    Text("Ultimo usato").tag(-1)
                    ForEach(settings.visibleTabs, id: \.rawValue) { tab in
                        Text(tab.title).tag(tab.rawValue)
                    }
                }
            }

            Section("Ordine e visibilità delle schede") {
                ForEach(settings.orderedTabs, id: \.rawValue) { tab in
                    HStack {
                        Toggle(tab.title, isOn: Binding(
                            get: { settings.visibleTabs.contains(tab) },
                            set: { settings.setTab(tab, visible: $0) }
                        ))
                        .disabled(settings.visibleTabs.count == 1 && settings.visibleTabs.contains(tab))
                        Button { settings.moveTab(tab, offset: -1) } label: { Image(systemName: "arrow.up") }
                            .disabled(settings.orderedTabs.first == tab).help("Sposta prima")
                        Button { settings.moveTab(tab, offset: 1) } label: { Image(systemName: "arrow.down") }
                            .disabled(settings.orderedTabs.last == tab).help("Sposta dopo")
                    }
                }
                Text("I gesti seguono questo ordine e saltano le schede nascoste. Mantieni almeno una scheda visibile.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            // ── Moduli ───────────────────────────────────────────────────────
            Section("Moduli") {
                Toggle("Now Playing", isOn: $settings.nowPlayingEnabled)
                Toggle("Lettura generica della riproduzione", isOn: $settings.systemMediaEnabled)
                    .disabled(!settings.nowPlayingEnabled)
                Text(media.status).font(.system(size: 11)).foregroundStyle(.secondary)
                Toggle("Rilevamento browser alternativo", isOn: $settings.browserObserverEnabled)
                Toggle("Ricorda i file della shelf al riavvio", isOn: $settings.shelfPersistenceEnabled)
                Text("Aggiungi i file alla Shelf trascinandoli sull’isola. Usa Sposta nella Shelf per scegliere una cartella dentro Documenti.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            // ── Tema ─────────────────────────────────────────────────────────
            Section("Tema") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Colore accento")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        ForEach(0..<ModuleSettings.accentColors.count, id: \.self) { idx in
                            let color = ModuleSettings.accentColors[idx]
                            let isSelected = settings.accentColorIndex == idx
                            ZStack {
                                Circle().fill(color).frame(width: 24, height: 24)
                                if isSelected {
                                    Circle()
                                        .strokeBorder(color, lineWidth: 2)
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(idx == 0 ? .black : .white)
                                }
                            }
                            .frame(width: 34, height: 34)
                            .contentShape(Circle())
                            .onTapGesture { settings.accentColorIndex = idx }
                            .animation(.interpolatingSpring(mass: 1.0, stiffness: 560, damping: 44), value: isSelected)
                        }
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            }

            // ── FileHub ──────────────────────────────────────────────────────
            Section("FileHub — cartella di output") {
                HStack(spacing: 8) {
                    Text(settings.outputDirectory.path)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Cambia…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.prompt = "Scegli"
                        panel.message = "Scegli la cartella dove salvare i file convertiti"
                        if panel.runModal() == .OK, let url = panel.url {
                            settings.outputDirectory = url
                        }
                    }
                    .fixedSize()
                }
                Button("Ripristina Desktop") {
                    settings.outputDirectory = FileManager.default
                        .homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
                }
                .foregroundColor(.secondary)
                .font(.system(size: 11))
            }

            // ── Sistema ──────────────────────────────────────────────────────
            Section("Sistema") {
                Toggle("Avvia al login", isOn: $settings.launchAtLogin)
                Toggle("Scorciatoia globale ⌃⌥Spazio (apri/chiudi)", isOn: $settings.hotkeyEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 700)
    }

}
