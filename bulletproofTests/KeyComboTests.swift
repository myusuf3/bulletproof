import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import bulletproof

struct KeyComboTests {
    @Test func displayStringUsesCanonicalModifierOrder() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_P),
                             modifiers: [.command, .shift, .option, .control])
        #expect(combo.displayString == "⌃⌥⇧⌘P")
    }

    @Test func defaultIsCommandShiftP() {
        #expect(KeyCombo.default.displayString == "⇧⌘P")
    }

    @Test func symbolTableCoversSpecialKeys() {
        #expect(KeyCombo.keySymbol(for: UInt32(kVK_Space)) == "Space")
        #expect(KeyCombo.keySymbol(for: UInt32(kVK_LeftArrow)) == "←")
        #expect(KeyCombo.keySymbol(for: UInt32(kVK_F5)) == "F5")
        #expect(KeyCombo.keySymbol(for: 9999) == "?")
    }

    @Test func carbonModifierBits() {
        let combo = KeyCombo(keyCode: 0, modifiers: [.command, .shift, .option, .control])
        #expect(combo.carbonModifiers == UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey) | UInt32(controlKey))
        #expect(KeyCombo(keyCode: 0, modifiers: .command).carbonModifiers == UInt32(cmdKey))
    }

    @Test func codableRoundTrip() throws {
        let original = KeyCombo(keyCode: UInt32(kVK_ANSI_Quote), modifiers: [.command, .option])
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func stripsDeviceDependentFlags() {
        let raw = NSEvent.ModifierFlags([.command]).union(NSEvent.ModifierFlags(rawValue: 0x8))
        let combo = KeyCombo(keyCode: 0, modifiers: raw)
        #expect(combo.modifiers == .command)
    }
}

struct KeyComboValidatorTests {
    @Test func noModifierRejected() {
        #expect(KeyComboValidator.validate(KeyCombo(keyCode: UInt32(kVK_ANSI_P), modifiers: [])) == .needsModifier)
    }

    @Test func shiftAloneRejected() {
        #expect(KeyComboValidator.validate(KeyCombo(keyCode: UInt32(kVK_ANSI_P), modifiers: .shift)) == .needsModifier)
    }

    @Test func systemReservedRejected() {
        for combo in [
            KeyCombo(keyCode: UInt32(kVK_Space), modifiers: .command),
            KeyCombo(keyCode: UInt32(kVK_Space), modifiers: .control),
            KeyCombo(keyCode: UInt32(kVK_Tab), modifiers: .command),
        ] {
            guard case .reservedBySystem = KeyComboValidator.validate(combo) else {
                Issue.record("Expected \(combo.displayString) to be reserved")
                return
            }
        }
    }

    @Test func commandOnlyChordsRejected() {
        for keyCode in [UInt32(kVK_ANSI_E), UInt32(kVK_ANSI_Q), UInt32(kVK_ANSI_C)] {
            let combo = KeyCombo(keyCode: keyCode, modifiers: .command)
            #expect(KeyComboValidator.validate(combo) == .conflictsWithAppShortcuts)
        }
    }

    @Test func commandPlusSecondModifierAccepted() {
        #expect(KeyComboValidator.validate(KeyCombo(keyCode: UInt32(kVK_ANSI_E), modifiers: [.command, .shift])) == .ok)
        #expect(KeyComboValidator.validate(KeyCombo(keyCode: UInt32(kVK_ANSI_E), modifiers: [.control, .option])) == .ok)
    }

    @Test func defaultComboAccepted() {
        #expect(KeyComboValidator.validate(.default) == .ok)
    }
}
