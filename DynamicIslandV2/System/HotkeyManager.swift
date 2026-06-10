import Carbon
import AppKit

/// Hotkey globale via Carbon RegisterEventHotKey: non richiede permessi di
/// Accessibility e non intercetta nessun altro evento — il sistema consegna
/// solo la combinazione registrata (⌃⌥Spazio).
final class HotkeyManager {
    var onActivate: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature = OSType(0x444E4948) // "DNIH"

    func register() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onActivate?() }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        // ⌃⌥Spazio (kVK_Space = 49)
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(UInt32(kVK_Space),
                            UInt32(controlKey | optionKey),
                            hotKeyID,
                            GetApplicationEventTarget(),
                            0,
                            &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let ref = handlerRef { RemoveEventHandler(ref); handlerRef = nil }
    }

    deinit { unregister() }
}
