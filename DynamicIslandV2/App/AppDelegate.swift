import AppKit
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        windowManager = WindowManager()
        windowManager?.show()
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
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Esci", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
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
