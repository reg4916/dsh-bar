import Carbon

/// Global hotkey (default ⌥⌘D) that toggles the popover. Carbon's
/// RegisterEventHotKey works for an accessory app without Accessibility
/// permission, unlike NSEvent global monitors.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var isRegistered = false
    var onPress: (() -> Void)?

    func register() {
        guard !isRegistered else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().onPress?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installStatus == noErr else { return }

        let identifier = EventHotKeyID(signature: OSType(0x44534252), id: 1) // "DSBR"
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_D),
            UInt32(cmdKey | optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        isRegistered = status == noErr
        if !isRegistered {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            self.handlerRef = nil
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
        isRegistered = false
    }
}
