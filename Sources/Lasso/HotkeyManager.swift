import Carbon.HIToolbox
import AppKit

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private static var handler: (() -> Void)?

    /// Registers the given shortcut as a global hotkey.
    init(shortcut: Shortcut, handler: @escaping () -> Void) {
        HotkeyManager.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                DispatchQueue.main.async { HotkeyManager.handler?() }
                return noErr
            },
            1, &eventType, nil, nil
        )

        register(shortcut)
    }

    /// Swaps the global hotkey to a new shortcut.
    func register(_ shortcut: Shortcut) {
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4354_5321), id: 1) // "CTS!"
        RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}
