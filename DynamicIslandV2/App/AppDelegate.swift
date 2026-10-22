import AppKit
import Combine
import Sparkle
import SwiftUI

/// Finestra che si chiude anche con Esc e Cmd+W (l'app è accessory,
/// quindi non c'è il menu File che normalmente gestisce Cmd+W).
private final class ClosableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "w" {
            close()
        } else {
            super.keyDown(with: event)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowManager: WindowManager?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var helpWindow: NSWindow?
    private var statsItems: [NSStatusItem] = []
    private var statsSubscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        windowManager = WindowManager()
        windowManager?.show()
        setupStatsMenuBar()
        AppUpdater.shared.start()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            // styleMask passato all'init: riassegnarlo dopo la creazione ricrea i
            // bottoni del titolo, che restano inattivi finché la finestra non si muove.
            let window = ClosableWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.title = "Dynamic Island — Impostazioni"
            window.isReleasedWhenClosed = false
            window.center()
            // Torna ad .accessory quando la finestra viene chiusa
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.settingsWindow = nil
                if self?.helpWindow == nil {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
            settingsWindow = window
        }
        // Serve .regular per portare in primo piano una finestra da un'app accessory
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openHelp() {
        if helpWindow == nil {
            let window = ClosableWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = NSHostingController(rootView: HelpView())
            window.title = "Dynamic Island — Guida"
            window.isReleasedWhenClosed = false
            window.center()
            // Torna ad .accessory quando la finestra viene chiusa
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.helpWindow = nil
                if self?.settingsWindow == nil {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
            helpWindow = window
        }
        // Serve .regular per portare in primo piano una finestra da un'app accessory
        NSApp.setActivationPolicy(.regular)
        helpWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = Self.menuBarIcon
            button.toolTip = "Dynamic Island"
            button.setAccessibilityLabel("Dynamic Island")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Dynamic Island", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Impostazioni…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Guida…", action: #selector(openHelp), keyEquivalent: ""))
        let updatesItem = NSMenuItem(
            title: "Controlla aggiornamenti…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updatesItem.target = AppUpdater.shared.controller
        menu.addItem(updatesItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Esci", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func setupStatsMenuBar() {
        ModuleSettings.shared.$statsMenuBarEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                self.statsItems.forEach { NSStatusBar.system.removeStatusItem($0) }
                self.statsItems.removeAll()
                if enabled {
                    for index in 0..<3 {
                        let item = NSStatusBar.system.statusItem(withLength: index == 2 ? 54 : 28)
                        item.button?.target = self
                        item.button?.action = #selector(self.openStats)
                        item.button?.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
                        self.statsItems.append(item)
                    }
                    self.updateStatsMenuBar(SystemStatsMonitor.shared.snapshot)
                }
            }.store(in: &statsSubscriptions)
        SystemStatsMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateStatsMenuBar($0) }
            .store(in: &statsSubscriptions)
    }

    private func updateStatsMenuBar(_ stats: SystemStatsSnapshot) {
        guard statsItems.count == 3 else { return }
        let values = [SystemStatsSnapshot.percent(stats.cpu), SystemStatsSnapshot.percent(stats.memory)]
        for index in 0..<2 {
            let label = index == 0 ? "CPU" : "RAM"
            let button = statsItems[index].button
            button?.image = Self.statsImage(width: 28, rows: [
                (label, 7, .medium), (values[index], 11, .bold)
            ])
            button?.imagePosition = .imageOnly
            button?.toolTip = label + " " + values[index] + " — clicca per aprire Stats"
            button?.setAccessibilityLabel(label + " " + values[index])
        }
        let download = "↓ " + Self.compactNetworkRate(stats.download)
        let upload = "↑ " + Self.compactNetworkRate(stats.upload)
        let network = statsItems[2].button
        network?.image = Self.statsImage(width: 54, rows: [
            (download, 9, .medium), (upload, 9, .medium)
        ])
        network?.imagePosition = .imageOnly
        network?.toolTip = "Download: " + SystemStatsSnapshot.rate(stats.download)
            + "\nUpload: " + SystemStatsSnapshot.rate(stats.upload)
        network?.setAccessibilityLabel("Download " + download + ", upload " + upload)
    }

    private static func compactNetworkRate(_ value: Double?) -> String {
        guard let value else { return "— B/s" }
        let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var rate = max(0, value)
        var unit = 0
        while rate >= 1024, unit < units.count - 1 {
            rate /= 1024
            unit += 1
        }
        return String(format: rate < 10 && unit > 0 ? "%.1f %@" : "%.0f %@", rate, units[unit])
    }

    private static func statsImage(width: CGFloat, rows: [(String, CGFloat, NSFont.Weight)]) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: true) { _ in
            for (index, row) in rows.enumerated() {
                let text = row.0 as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: row.1, weight: row.2),
                    .foregroundColor: NSColor.black
                ]
                let size = text.size(withAttributes: attributes)
                let y: CGFloat = index == 0 ? (rows[0].1 == 7 ? 2 : 0) : (rows[0].1 == 7 ? 9 : 10)
                text.draw(at: NSPoint(x: (width - size.width) / 2, y: y), withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func openStats() {
        windowManager?.notchState.expand(tab: .stats)
        windowManager?.notchState.switchTab(.stats)
    }

    /// A vector template stays crisp on Retina displays and follows the menu bar appearance.
    private static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            let island = NSBezierPath(
                roundedRect: NSRect(x: 1, y: 4, width: 16, height: 10),
                xRadius: 5,
                yRadius: 5
            )
            island.windingRule = .evenOdd
            island.append(NSBezierPath(
                roundedRect: NSRect(x: 4, y: 8.25, width: 4, height: 1.5),
                xRadius: 0.75,
                yRadius: 0.75
            ))
            island.append(NSBezierPath(ovalIn: NSRect(x: 11.5, y: 8, width: 2, height: 2)))
            island.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Dynamic Island"
        return image
    }()
}
