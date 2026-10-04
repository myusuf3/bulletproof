import Carbon.HIToolbox

/// Thin wrapper over the Carbon hot key API - the only permission-free way to
/// register a global shortcut. One instance per shortcut, told apart by id.
@MainActor final class HotkeyManager {
    var onHotkey: (() -> Void)?
    /// Fires when the chord's key comes back up - hold-to-talk's stop.
    var onRelease: (() -> Void)?
    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(id: UInt32 = 1) {
        self.id = id
    }

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
        let hotKeyID = EventHotKeyID(signature: OSType(0x424C_5450) /* 'BLTP' */, id: id)
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
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        // The handler must be a C function pointer; self travels via userData.
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            // Every manager's handler sees every hot key; pass on the others'
            // so the next handler in the chain gets them.
            guard hotKeyID.id == manager.id else { return OSStatus(eventNotHandledErr) }
            let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            // Carbon dispatches on the main run loop, but assumeIsolated is a
            // hard trap if that ever changes - fall back to a hop instead.
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    released ? manager.onRelease?() : manager.onHotkey?()
                }
            } else {
                Task { @MainActor in
                    released ? manager.onRelease?() : manager.onHotkey?()
                }
            }
            return noErr
        }, specs.count, &specs, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
    }
}
