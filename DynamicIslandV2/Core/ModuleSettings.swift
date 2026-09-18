import Foundation
import Combine
import SwiftUI

final class ModuleSettings: ObservableObject {
    static let shared = ModuleSettings()
    private let defaults: UserDefaults
    private let usesSystemServices: Bool

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
    @Published var systemMediaEnabled: Bool = true { didSet { save() } }
    @Published var browserObserverEnabled: Bool  = true  { didSet { save() } }
    @Published var compactSideViewsEnabled: Bool = true  { didSet { save() } }
    @Published var compactActivitiesEnabled: Bool = true { didSet { save() } }
    @Published var notchOpacity: Double          = 1.0   { didSet { save() } }
    @Published var lastActiveTab: Int            = 0     { didSet { save() } }
    @Published var accentColorIndex: Int         = 0     { didSet { save() } }

    // ── Interazione ──────────────────────────────────────────────────────────
    /// 0 = click, 1 = hover
    @Published var openModeIndex: Int            = 0     { didSet { save() } }
    /// Ritardo hover in secondi (0.2 – 1.0)
    @Published var hoverDelay: Double            = 0.4   { didSet { save() } }
    /// Mostra la barra dei tab quando il notch è aperto
    @Published var showTabBar: Bool              = true  { didSet { save() } }
    @Published private(set) var tabOrder = ExpandedTab.allCases.map(\.rawValue) { didSet { save() } }
    @Published private(set) var hiddenTabs: [Int] = [] { didSet { save() } }

    var orderedTabs: [ExpandedTab] { tabOrder.compactMap(ExpandedTab.init(rawValue:)) }
    var visibleTabs: [ExpandedTab] { orderedTabs.filter { !hiddenTabs.contains($0.rawValue) } }

    func setTab(_ tab: ExpandedTab, visible: Bool) {
        if visible { hiddenTabs.removeAll { $0 == tab.rawValue } }
        else if visibleTabs.count > 1, !hiddenTabs.contains(tab.rawValue) { hiddenTabs.append(tab.rawValue) }
        if !visibleTabs.contains(where: { $0.rawValue == defaultTabIndex }) { defaultTabIndex = -1 }
    }

    func moveTab(_ tab: ExpandedTab, offset: Int) {
        guard let index = tabOrder.firstIndex(of: tab.rawValue), tabOrder.indices.contains(index + offset) else { return }
        tabOrder.swapAt(index, index + offset)
    }
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
            guard !isLoading else { return }
            if usesSystemServices { LaunchAtLoginManager.shared.isEnabled = launchAtLogin }
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
            if defaultTabIndex >= 0, let fixed = ExpandedTab(rawValue: defaultTabIndex), visibleTabs.contains(fixed) {
                return fixed
            }
            return visibleTabs.first(where: { $0.rawValue == lastActiveTab }) ?? visibleTabs.first ?? .nowPlaying
        }
        set { if lastActiveTab != newValue.rawValue { lastActiveTab = newValue.rawValue } }
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

    init(defaults: UserDefaults = .standard, usesSystemServices: Bool = true) {
        self.defaults = defaults
        self.usesSystemServices = usesSystemServices
        load()
    }

    private func save() {
        guard !isLoading else { return }
        func persist(_ value: Any, forKey key: String) {
            if let previous = defaults.object(forKey: key) as? NSObject,
               previous.isEqual(value) { return }
            defaults.set(value, forKey: key)
        }
        persist(compactActivitiesEnabled, forKey: "mod.compactActivities")
        persist(systemMediaEnabled, forKey: "mod.systemMedia")
        persist(nowPlayingEnabled,       forKey: "mod.nowPlaying")
        persist(browserObserverEnabled,  forKey: "mod.browser")
        persist(compactSideViewsEnabled, forKey: "mod.compactSideViews")
        persist(notchOpacity,            forKey: "mod.notchOpacity")
        persist(lastActiveTab,           forKey: "mod.lastActiveTab")
        persist(accentColorIndex,        forKey: "mod.accentColor")
        persist(openModeIndex,           forKey: "mod.openMode")
        persist(hoverDelay,              forKey: "mod.hoverDelay")
        persist(showTabBar,              forKey: "mod.showTabBar")
        persist(tabOrder, forKey: "mod.tabOrder")
        persist(hiddenTabs, forKey: "mod.hiddenTabs")
        persist(defaultTabIndex,         forKey: "mod.defaultTab")
        persist(launchAtLogin,           forKey: "mod.launchAtLogin")
        persist(preferredDisplayID,      forKey: "mod.preferredDisplay")
        persist(hotkeyEnabled,           forKey: "mod.hotkey")
        persist(shelfPersistenceEnabled, forKey: "mod.shelfPersistence")
        persist(outputDirectory.path,    forKey: "mod.outputDirectory")
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        let d = defaults
        let known = ExpandedTab.allCases.map(\.rawValue)
        let savedOrder = d.array(forKey: "mod.tabOrder") as? [Int] ?? known
        var seen = Set<Int>()
        tabOrder = (savedOrder + known).filter { known.contains($0) && seen.insert($0).inserted }
        hiddenTabs = (d.array(forKey: "mod.hiddenTabs") as? [Int] ?? []).filter { known.contains($0) }
        if visibleTabs.isEmpty { hiddenTabs.removeAll { $0 == tabOrder[0] } }
        func bool(_ key: String, default def: Bool) -> Bool {
            d.object(forKey: key) != nil ? d.bool(forKey: key) : def
        }
        compactActivitiesEnabled = bool("mod.compactActivities", default: true)
        systemMediaEnabled = bool("mod.systemMedia", default: true)
        nowPlayingEnabled       = bool("mod.nowPlaying",       default: true)
        browserObserverEnabled  = bool("mod.browser",          default: true)
        compactSideViewsEnabled = bool("mod.compactSideViews", default: true)
        notchOpacity            = d.object(forKey: "mod.notchOpacity") != nil ? d.double(forKey: "mod.notchOpacity") : 1.0
        showTabBar              = bool("mod.showTabBar",        default: true)
        lastActiveTab           = d.object(forKey: "mod.lastActiveTab")   != nil ? d.integer(forKey: "mod.lastActiveTab")   : 0
        accentColorIndex        = d.object(forKey: "mod.accentColor")     != nil ? d.integer(forKey: "mod.accentColor")     : 0
        openModeIndex           = d.object(forKey: "mod.openMode")        != nil ? d.integer(forKey: "mod.openMode")        : 0
        defaultTabIndex         = d.object(forKey: "mod.defaultTab")      != nil ? d.integer(forKey: "mod.defaultTab")      : -1
        // L’ex tab Meteo apre ora il blocco note; gli altri ID restano invariati.
        if lastActiveTab == 4 { lastActiveTab = ExpandedTab.notes.rawValue }
        if defaultTabIndex == 4 { defaultTabIndex = ExpandedTab.notes.rawValue }
        if !visibleTabs.contains(where: { $0.rawValue == defaultTabIndex }) { defaultTabIndex = -1 }
        hoverDelay              = d.object(forKey: "mod.hoverDelay")      != nil ? d.double(forKey: "mod.hoverDelay")       : 0.4
        launchAtLogin           = usesSystemServices ? LaunchAtLoginManager.shared.isEnabled : bool("mod.launchAtLogin", default: false)
        preferredDisplayID      = d.object(forKey: "mod.preferredDisplay") != nil ? d.integer(forKey: "mod.preferredDisplay") : 0
        hotkeyEnabled           = bool("mod.hotkey",           default: true)
        shelfPersistenceEnabled = bool("mod.shelfPersistence", default: true)
        notchOpacity = notchOpacity.isFinite ? min(1, max(0.3, notchOpacity)) : 1
        hoverDelay = hoverDelay.isFinite ? min(1, max(0.2, hoverDelay)) : 0.4
        if !(0...2).contains(openModeIndex) { openModeIndex = 0 }
        if !Self.accentColors.indices.contains(accentColorIndex) { accentColorIndex = 0 }
        if let path = d.string(forKey: "mod.outputDirectory"), !path.isEmpty {
            outputDirectory = URL(fileURLWithPath: path)
        }
    }
}
