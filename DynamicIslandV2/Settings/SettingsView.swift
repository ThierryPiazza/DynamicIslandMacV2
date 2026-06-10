import SwiftUI
import AppKit
import CoreLocation

struct SettingsView: View {
    @ObservedObject private var settings = ModuleSettings.shared

    private let tabNames = ["Now Playing", "Shelf", "Clipboard", "Calendario", "Meteo"]

    // Ricerca città meteo
    @State private var citySearchText: String = ""
    @State private var citySearchState: CitySearchState = .idle

    enum CitySearchState {
        case idle, searching, found(String, Double, Double), notFound, error
    }

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
                    ForEach(0..<tabNames.count, id: \.self) { i in
                        Text(tabNames[i]).tag(i)
                    }
                }
            }

            // ── Meteo ────────────────────────────────────────────────────────
            Section("Meteo") {
                Toggle("Posizione fissa", isOn: $settings.weatherUseFixed)

                if settings.weatherUseFixed {
                    if !settings.weatherFixedCity.isEmpty {
                        HStack {
                            Image(systemName: "mappin.circle.fill").foregroundColor(.accentColor)
                            Text(settings.weatherFixedCity).font(.system(size: 13))
                            Spacer()
                            Button("Cambia") { settings.weatherFixedCity = ""; citySearchState = .idle }
                                .buttonStyle(.plain).foregroundColor(.accentColor).font(.system(size: 12))
                        }
                    } else {
                        HStack(spacing: 6) {
                            TextField("Nome città…", text: $citySearchText)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { searchCity() }
                            Button(action: searchCity) {
                                if case .searching = citySearchState {
                                    ProgressView().scaleEffect(0.7)
                                } else {
                                    Image(systemName: "magnifyingglass")
                                }
                            }
                            .frame(width: 28)
                            .disabled(citySearchText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        switch citySearchState {
                        case .notFound:
                            Text("Città non trovata").font(.system(size: 11)).foregroundColor(.red)
                        case .error:
                            Text("Errore di ricerca").font(.system(size: 11)).foregroundColor(.red)
                        case .found(let city, _, _):
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                Text(city).font(.system(size: 12))
                                Spacer()
                                Button("Usa questa") {
                                    if case .found(let c, let lat, let lon) = citySearchState {
                                        settings.weatherFixedCity = c
                                        settings.weatherFixedLat  = lat
                                        settings.weatherFixedLon  = lon
                                        citySearchState = .idle
                                        citySearchText  = ""
                                    }
                                }
                                .buttonStyle(.plain).foregroundColor(.accentColor)
                            }
                        default: EmptyView()
                        }
                    }
                }
            }

            // ── Moduli ───────────────────────────────────────────────────────
            Section("Moduli") {
                Toggle("Now Playing", isOn: $settings.nowPlayingEnabled)
                Toggle("Browser (Arc, Chrome, Safari…)", isOn: $settings.browserObserverEnabled)
                Toggle("Ricorda i file della shelf al riavvio", isOn: $settings.shelfPersistenceEnabled)
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

    // MARK: - City search

    private func searchCity() {
        let query = citySearchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        citySearchState = .searching

        CLGeocoder().geocodeAddressString(query) { placemarks, error in
            DispatchQueue.main.async {
                if error != nil {
                    citySearchState = .error
                    return
                }
                guard let place = placemarks?.first,
                      let loc   = place.location else {
                    citySearchState = .notFound
                    return
                }
                let city = place.locality
                    ?? place.administrativeArea
                    ?? place.country
                    ?? query
                citySearchState = .found(city, loc.coordinate.latitude, loc.coordinate.longitude)
            }
        }
    }
}
