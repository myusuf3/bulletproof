import AppKit
import Carbon.HIToolbox
import Testing
@testable import bulletproof

// Obscure chords so the tests never collide with the app's own registration
// (the test host registers the real shortcut at launch).
@MainActor
struct HotkeyManagerTests {
    @Test func registersUnregistersAndReregisters() {
        let manager = HotkeyManager()
        let combo = KeyCombo(keyCode: UInt32(kVK_F18), modifiers: [.control, .option])
        #expect(manager.register(combo))
        manager.unregister()
        #expect(manager.register(KeyCombo(keyCode: UInt32(kVK_F17), modifiers: [.control, .option, .shift])))
        manager.unregister()
    }

    @Test func replacingRegistrationSucceeds() {
        let manager = HotkeyManager()
        #expect(manager.register(KeyCombo(keyCode: UInt32(kVK_F16), modifiers: [.control, .option])))
        // register() replaces any prior registration without an explicit unregister.
        #expect(manager.register(KeyCombo(keyCode: UInt32(kVK_F15), modifiers: [.control, .option])))
        manager.unregister()
    }
}
