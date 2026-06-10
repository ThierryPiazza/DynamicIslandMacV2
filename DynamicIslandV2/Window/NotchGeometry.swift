import AppKit
import CoreGraphics

struct NotchGeometry {
    let frame: CGRect
    let screen: NSScreen
    /// true = notch fisico dell'housing della fotocamera; false = island virtuale su Mac senza notch
    let hasPhysicalNotch: Bool

    // MARK: - Detection

    /// Restituisce la geometria del notch fisico sullo schermo indicato.
    /// Su Mac senza notch costruisce un rettangolo virtuale centrato in alto.
    static func detect(on screen: NSScreen) -> NotchGeometry {
        let insets = screen.safeAreaInsets
        let screenFrame = screen.frame

        if insets.top > 0 {
            // auxiliaryTopLeftArea/Right = aree menu bar ai lati del notch
            let leftW  = screen.auxiliaryTopLeftArea?.width  ?? 0
            let rightW = screen.auxiliaryTopRightArea?.width ?? 0
            let notchWidth  = screenFrame.width - leftW - rightW
            let notchHeight = insets.top
            let notchX = screenFrame.minX + leftW
            let notchY = screenFrame.maxY - notchHeight
            let frame = CGRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight)
            return NotchGeometry(frame: frame, screen: screen, hasPhysicalNotch: true)
        } else {
            // Island virtuale per Mac senza tacca fisica
            let notchWidth: CGFloat = 200
            let notchHeight: CGFloat = 32
            let notchX = screenFrame.midX - notchWidth / 2
            let notchY = screenFrame.maxY - notchHeight
            let frame = CGRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight)
            return NotchGeometry(frame: frame, screen: screen, hasPhysicalNotch: false)
        }
    }

    /// Rispetta lo schermo scelto dall'utente nelle impostazioni (preferredDisplayID);
    /// se è 0 (automatico) o il display scelto non è più collegato, fallback su detectOnMain.
    static func detectPreferred() -> NotchGeometry? {
        let pref = ModuleSettings.shared.preferredDisplayID
        if pref != 0, let screen = screenWithID(CGDirectDisplayID(pref)) {
            return detect(on: screen)
        }
        return detectOnMain()
    }

    static func screenWithID(_ id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
        }
    }

    /// Cerca prima il display integrato con notch fisico; se non trovato usa lo schermo principale.
    /// Questo garantisce che su Mac con notch il panel vada sempre sullo schermo interno,
    /// indipendentemente da quale sia impostato come "main" (es. monitor esterno primario).
    static func detectOnMain() -> NotchGeometry? {
        if let builtIn = builtInNotchedScreen() {
            return detect(on: builtIn)
        }
        guard let screen = NSScreen.main else { return nil }
        return detect(on: screen)
    }

    /// Restituisce lo schermo integrato con notch fisico, se presente.
    static func builtInNotchedScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard screen.safeAreaInsets.top > 0 else { return false }
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }
    }

    /// true se nessun display collegato è uno schermo integrato con notch fisico.
    static var noBuiltInNotch: Bool { builtInNotchedScreen() == nil }
}
