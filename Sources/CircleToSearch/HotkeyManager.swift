import Carbon.HIToolbox
import AppKit

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private static var handler: (() -> Void)?

    /// Registers ⌥⌘Space as a global hotkey.
    init(handler: @escaping () -> Void) {
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

        let hotKeyID = EventHotKeyID(signature: OSType(0x4354_5321), id: 1) // "CTS!"
        RegisterEventHotKey(
            UInt32(kVK_Space),            // 49
            UInt32(optionKey | cmdKey),   // ⌥⌘
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}
