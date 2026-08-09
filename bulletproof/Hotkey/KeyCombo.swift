import AppKit
import Carbon.HIToolbox

nonisolated struct KeyCombo: Codable, Hashable {
    /// Carbon kVK virtual keycode.
    var keyCode: UInt32
    /// NSEvent.ModifierFlags raw value, device-independent flags only.
    var modifierRawValue: UInt

    static let `default` = KeyCombo(keyCode: UInt32(kVK_ANSI_P), modifiers: [.command, .shift])

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierRawValue = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
    }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
    }

    /// RegisterEventHotKey wants Carbon's own modifier constants.
    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }

    /// Canonical macOS modifier ordering: ⌃ ⌥ ⇧ ⌘, then the key symbol.
    var displayString: String {
        modifierSymbols.joined() + Self.keySymbol(for: keyCode)
    }

    /// Modifier symbols in display order, for rendering one keycap per modifier.
    var modifierSymbols: [String] {
        var symbols: [String] = []
        if modifiers.contains(.control) { symbols.append("⌃") }
        if modifiers.contains(.option) { symbols.append("⌥") }
        if modifiers.contains(.shift) { symbols.append("⇧") }
        if modifiers.contains(.command) { symbols.append("⌘") }
        return symbols
    }

    static func keySymbol(for keyCode: UInt32) -> String {
        symbols[keyCode] ?? "?"
    }

    // Static ANSI table rather than UCKeyTranslate: layout-aware translation is
    // more code than this app needs, and the recorder always re-captures the
    // physical keyCode anyway.
    private static let symbols: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "⏎", UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Delete): "⌫", UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_ANSI_Grave): "`", UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_Equal): "=", UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Period): ".", UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Semicolon): ";", UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Backslash): "\\",
    ]
}

nonisolated enum KeyComboValidator {
    enum Verdict: Equatable {
        case ok
        case needsModifier
        case conflictsWithAppShortcuts
        case reservedBySystem(String)
    }

    private static let reserved: [(combo: KeyCombo, owner: String)] = [
        (KeyCombo(keyCode: UInt32(kVK_Space), modifiers: .command), "Spotlight"),
        (KeyCombo(keyCode: UInt32(kVK_Space), modifiers: .control), "input source switching"),
        (KeyCombo(keyCode: UInt32(kVK_Tab), modifiers: .command), "the app switcher"),
    ]

    static func validate(_ combo: KeyCombo) -> Verdict {
        // Shift alone just types capitals; require a command-like modifier.
        guard !combo.modifiers.intersection([.command, .option, .control]).isEmpty else {
            return .needsModifier
        }
        if let hit = reserved.first(where: { $0.combo == combo }) {
            return .reservedBySystem("\(combo.displayString) is used by \(hit.owner).")
        }
        // A global hotkey steals its chord from every app. Plain ⌘+key is the
        // namespace of app menu shortcuts (⌘E is Use Selection for Find, ⌘Q
        // quits, ...), so require a second modifier alongside ⌘.
        if combo.modifiers.intersection([.command, .shift, .option, .control]) == [.command] {
            return .conflictsWithAppShortcuts
        }
        return .ok
    }
}
