import Foundation
import Combine
import SwiftUI

final class ModuleSettings: ObservableObject {
    static let shared = ModuleSettings()

    // Preset accent colors — index 0 = white (default)
    static let accentColors: [Color] = [
        .white,
        Color(red: 0.30, green: 0.60, blue: 1.00),  // Blu
        Color(red: 0.65, green: 0.35, blue: 1.00),  // Viola
        Color(red: 0.25, green: 0.85, blue: 0.50),  // Verde
        Color(red: 1.00, green: 0.62, blue: 0.15),  // Arancio
        Color(red: 1.00, green: 0.30, blue: 0.40),  // Rosso
    ]

    @Published var nowPlayingEnabled: Bool       = true  { didSet { save() } }
    @Published var browserObserverEnabled: Bool  = true  { didSet { save() } }
    @Published var compactSideViewsEnabled: Bool = true  { didSet { save() } }
    @Published var notchOpacity: Double          = 1.0   { didSet { save() } }
    @Published var lastActiveTab: Int            = 0     { didSet { save() } }
    @Published var accentColorIndex: Int         = 0     { didSet { save() } }

    // ── Meteo ─────────────────────────────────────────────────────────────────
    @Published var weatherUseFixed: Bool   = false { didSet { save() } }
    @Published var weatherFixedCity: String = ""   { didSet { save() } }
    @Published var weatherFixedLat: Double  = 0    { didSet { save() } }
    @Published var weatherFixedLon: Double  = 0    { didSet { save() } }

    // ── Interazione ──────────────────────────────────────────────────────────
    /// 0 = click, 1 = hover
    @Published var openModeIndex: Int            = 0     { didSet { save() } }
    /// Ritardo hover in secondi (0.2 – 1.0)
    @Published var hoverDelay: Double            = 0.4   { didSet { save() } }
    /// Mostra la barra dei tab quando il notch è aperto
    @Published var showTabBar: Bool              = true  { didSet { save() } }
    /// Usa sempre un tab specifico anziché ricordare l'ultimo (−1 = ricorda ultimo)
    @Published var defaultTabIndex: Int          = -1    { didSet { save() } }

    // ── Schermo ──────────────────────────────────────────────────────────────
    /// CGDirectDisplayID dello schermo scelto per il notch; 0 = automatico
    /// (display integrato con notch fisico, altrimenti schermo principale).
    @Published var preferredDisplayID: Int = 0 { didSet { save() } }

    // ── Sistema ──────────────────────────────────────────────────────────────
    /// Hotkey globale ⌃⌥Spazio per aprire/chiudere l'island.
    @Published var hotkeyEnabled: Bool = true { didSet { save() } }
    /// Mantieni i file della shelf tra un riavvio e l'altro dell'app.
    @Published var shelfPersistenceEnabled: Bool = true { didSet { save() } }

    @Published var launchAtLogin: Bool = false {
        didSet {
            LaunchAtLoginManager.shared.isEnabled = launchAtLogin
            save()
        }
    }
    @Published var outputDirectory: URL = FileManager.default
        .homeDirectoryForCurrentUser.appendingPathComponent("Desktop") {
        didSet { save() }
    }

    /// Hover apre il notch (mode 1 = solo hover, mode 2 = mix)
    var openOnHover: Bool { openModeIndex == 1 || openModeIndex == 2 }
    /// Click apre il notch (mode 0 = solo click, mode 2 = mix)
    var openOnClick: Bool { openModeIndex == 0 || openModeIndex == 2 }

    var lastTab: ExpandedTab {
        get {
            // Se c'è un tab fisso scelto dall'utente, usa quello; altrimenti l'ultimo usato
            if defaultTabIndex >= 0, let fixed = ExpandedTab.allCases[safe: defaultTabIndex] {
                return fixed
            }
            return ExpandedTab.allCases[safe: lastActiveTab] ?? .nowPlaying
        }
        set { lastActiveTab = ExpandedTab.allCases.firstIndex(of: newValue) ?? 0 }
    }

    var accentColor: Color {
        let colors = ModuleSettings.accentColors
        let idx = max(0, min(accentColorIndex, colors.count - 1))
        return colors[idx]
    }

    /// Durante load() i didSet scattano a ogni assegnazione: senza questo flag
    /// il primo save() sovrascriverebbe su disco i valori non ancora caricati
    /// con i default, azzerando le impostazioni a ogni avvio.
    private var isLoading = false

    private init() { load() }

    private func save() {
        guard !isLoading else { return }
        let d = UserDefaults.standard
        d.set(weatherUseFixed,         forKey: "mod.weatherFixed")
        d.set(weatherFixedCity,        forKey: "mod.weatherCity")
        d.set(weatherFixedLat,         forKey: "mod.weatherLat")
        d.set(weatherFixedLon,         forKey: "mod.weatherLon")
        d.set(nowPlayingEnabled,       forKey: "mod.nowPlaying")
        d.set(browserObserverEnabled,  forKey: "mod.browser")
        d.set(compactSideViewsEnabled, forKey: "mod.compactSideViews")
        d.set(notchOpacity,            forKey: "mod.notchOpacity")
        d.set(lastActiveTab,           forKey: "mod.lastActiveTab")
        d.set(accentColorIndex,        forKey: "mod.accentColor")
        d.set(openModeIndex,           forKey: "mod.openMode")
        d.set(hoverDelay,              forKey: "mod.hoverDelay")
        d.set(showTabBar,              forKey: "mod.showTabBar")
        d.set(defaultTabIndex,         forKey: "mod.defaultTab")
        d.set(launchAtLogin,           forKey: "mod.launchAtLogin")
        d.set(preferredDisplayID,      forKey: "mod.preferredDisplay")
        d.set(hotkeyEnabled,           forKey: "mod.hotkey")
        d.set(shelfPersistenceEnabled, forKey: "mod.shelfPersistence")
        d.set(outputDirectory.path,    forKey: "mod.outputDirectory")
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        let d = UserDefaults.standard
        func bool(_ key: String, default def: Bool) -> Bool {
            d.object(forKey: key) != nil ? d.bool(forKey: key) : def
        }
        weatherUseFixed  = bool("mod.weatherFixed", default: false)
        weatherFixedCity = d.string(forKey: "mod.weatherCity") ?? ""
        weatherFixedLat  = d.object(forKey: "mod.weatherLat") != nil ? d.double(forKey: "mod.weatherLat") : 0
        weatherFixedLon  = d.object(forKey: "mod.weatherLon") != nil ? d.double(forKey: "mod.weatherLon") : 0
        nowPlayingEnabled       = bool("mod.nowPlaying",       default: true)
        browserObserverEnabled  = bool("mod.browser",          default: true)
        compactSideViewsEnabled = bool("mod.compactSideViews", default: true)
        notchOpacity            = d.object(forKey: "mod.notchOpacity") != nil ? d.double(forKey: "mod.notchOpacity") : 1.0
        showTabBar              = bool("mod.showTabBar",        default: true)
        lastActiveTab           = d.object(forKey: "mod.lastActiveTab")   != nil ? d.integer(forKey: "mod.lastActiveTab")   : 0
        accentColorIndex        = d.object(forKey: "mod.accentColor")     != nil ? d.integer(forKey: "mod.accentColor")     : 0
        openModeIndex           = d.object(forKey: "mod.openMode")        != nil ? d.integer(forKey: "mod.openMode")        : 0
        defaultTabIndex         = d.object(forKey: "mod.defaultTab")      != nil ? d.integer(forKey: "mod.defaultTab")      : -1
        hoverDelay              = d.object(forKey: "mod.hoverDelay")      != nil ? d.double(forKey: "mod.hoverDelay")       : 0.4
        launchAtLogin           = LaunchAtLoginManager.shared.isEnabled
        preferredDisplayID      = d.object(forKey: "mod.preferredDisplay") != nil ? d.integer(forKey: "mod.preferredDisplay") : 0
        hotkeyEnabled           = bool("mod.hotkey",           default: true)
        shelfPersistenceEnabled = bool("mod.shelfPersistence", default: true)
        if let path = d.string(forKey: "mod.outputDirectory") {
            outputDirectory = URL(fileURLWithPath: path)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
