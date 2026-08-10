import Carbon.HIToolbox

/// Thin wrapper over the Carbon hot key API - the only permission-free way to
/// register a global shortcut.
@MainActor final class HotkeyManager {
    var onHotkey: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    /// Returns false when the combo is already claimed - registration is
    /// exclusive, so a chord held by another app is genuinely refused rather
    /// than silently shared.
    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        unregister()
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x424C_5450) /* 'BLTP' */, id: 1)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotKeyID,
                                         GetEventDispatcherTarget(),
                                         OptionBits(kEventHotKeyExclusive), &ref)
        hotKeyRef = ref
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        // The handler must be a C function pointer; self travels via userData.
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, userData in
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue()
            // Carbon dispatches on the main run loop, but assumeIsolated is a
            // hard trap if that ever changes - fall back to a hop instead.
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    manager.onHotkey?()
                }
            } else {
                Task { @MainActor in
                    manager.onHotkey?()
                }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
    }
}
