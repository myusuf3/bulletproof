import SwiftUI
import Carbon.HIToolbox

/// Click-to-record shortcut field, shared by onboarding and Settings.
struct ShortcutRecorderView: View {
    let combo: KeyCombo
    let onChange: (KeyCombo) -> Void

    @State private var isRecording = false
    @State private var heldModifiers: NSEvent.ModifierFlags = []
    @State private var verdictMessage: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggleRecording) {
                Text(capsuleText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .frame(minWidth: 130)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(
                        Capsule().fill(isRecording ? Color.accentColor.opacity(0.15)
                                                   : Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        Capsule().strokeBorder(isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                                               lineWidth: isRecording ? 1.5 : 1)
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.15), value: isRecording)

            if let verdictMessage {
                Text(verdictMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if isRecording {
                Text("Press your shortcut, or ⎋ to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear { stopRecording() }
    }

    private var capsuleText: String {
        if isRecording {
            let held = KeyCombo(keyCode: 0, modifiers: heldModifiers).modifierSymbols.joined()
            return held.isEmpty ? "Recording…" : held + "…"
        }
        return combo.displayString
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        verdictMessage = nil
        heldModifiers = []
        HotkeyDispatcher.shared.isSuspended = true
        // Release the current chord so pressing it lands in the local monitor
        // (Carbon would otherwise consume it and the press would feel dead).
        HotkeyDispatcher.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
        heldModifiers = []
        HotkeyDispatcher.shared.isSuspended = false
        // Re-register whatever combo is current (the committed one on accept,
        // the old one on cancel).
        HotkeyDispatcher.shared.register(AppState.shared.shortcut)
    }

    /// Returns nil to swallow keystrokes while recording.
    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .flagsChanged:
            heldModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return nil
        case .keyDown:
            if event.keyCode == UInt16(kVK_Escape) && heldModifiers.isEmpty {
                stopRecording()
                return nil
            }
            let candidate = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags)
            switch KeyComboValidator.validate(candidate) {
            case .ok:
                stopRecording()
                if HotkeyDispatcher.shared.register(candidate) {
                    onChange(candidate)
                } else {
                    HotkeyDispatcher.shared.register(combo)
                    verdictMessage = "That shortcut is taken by another app."
                }
            case .needsModifier:
                verdictMessage = "Add at least one of ⌘ ⌥ ⌃."
            case .conflictsWithAppShortcuts:
                verdictMessage = "⌘ + a key belongs to app shortcuts (⌘E is Use Selection for Find). Add ⇧, ⌥, or ⌃."
            case .reservedBySystem(let message):
                verdictMessage = message
            }
            return nil
        default:
            return event
        }
    }
}
