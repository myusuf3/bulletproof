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

    @Test func duplicateChordIsRefusedExclusively() {
        // Registration must be exclusive, or the "taken by another app"
        // conflict message is a lie and chords get silently shared.
        let first = HotkeyManager()
        let second = HotkeyManager()
        let combo = KeyCombo(keyCode: UInt32(kVK_F14), modifiers: [.control, .option, .shift])
        #expect(first.register(combo))
        #expect(!second.register(combo))
        first.unregister()
        // Once released, the chord is claimable again.
        #expect(second.register(combo))
        second.unregister()
    }
}
