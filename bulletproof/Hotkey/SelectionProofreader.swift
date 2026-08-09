import AppKit
import Carbon.HIToolbox

/// The global hotkey flow: copy the frontmost app's selection with a synthetic
/// ⌘C, proofread it, paste the correction with ⌘V, and put the user's original
/// clipboard back.
@MainActor final class SelectionProofreader {
    private let appState: AppState
    private let notifier = UserNotifier()
    private var isRunning = false

    init(appState: AppState) {
        self.appState = appState
    }

    func run() {
        guard AccessibilityPermission.isTrusted else {
            AccessibilityPermission.requestWithPrompt()
            notifier.post(title: "Accessibility access needed",
                          body: "Grant bulletproof access in System Settings > Privacy & Security > Accessibility, then try again.")
            return
        }
        guard !isRunning else { return }
        isRunning = true
        Task {
            defer { isRunning = false }
            await performFlow()
        }
    }

    private func performFlow() async {
        let pboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pboard)
        let countBefore = pboard.changeCount

        // Wait for the user's physical chord to be released - a still-held
        // modifier can combine with the synthetic keystroke in the target app.
        await waitForModifierRelease()
        try? await Task.sleep(for: .milliseconds(50))
        KeyPoster.post(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        guard await changed(pboard, from: countBefore, within: .seconds(1)) else {
            notifier.post(title: "Nothing to proofread",
                          body: "Select some text first, then press \(appState.shortcut.displayString).")
            return
        }
        guard let text = pboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            notifier.post(title: "Nothing to proofread",
                          body: ProofreadingError.emptyInput.localizedDescription)
            snapshot.restore(to: pboard)
            return
        }

        let engine = appState.makeEngine()
        let corrected: String
        do {
            corrected = try await withTimeout(seconds: 55) { try await engine.proofread(text) }
        } catch {
            notifier.post(title: "Proofread failed", body: error.localizedDescription)
            snapshot.restore(to: pboard)
            return
        }

        // Read the selection bounds before ⌘V collapses the selection - the
        // corrected text lands exactly where the original sits.
        let flashRect = SelectionLocator.selectionScreenRect()

        pboard.clearContents()
        pboard.setString(corrected, forType: .string)
        KeyPoster.post(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)

        // Give the target app time to read the paste before restoring.
        try? await Task.sleep(for: .milliseconds(300))
        if let flashRect {
            SuccessFlashController.shared.flash(over: flashRect)
        } else {
            SuccessFlashController.shared.flashChip(near: NSEvent.mouseLocation)
        }
        snapshot.restore(to: pboard)
    }

    private func waitForModifierRelease(budget: Duration = .seconds(1)) async {
        let deadline = ContinuousClock.now + budget
        while ContinuousClock.now < deadline {
            let held = NSEvent.modifierFlags.intersection([.command, .shift, .option, .control])
            if held.isEmpty { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func changed(_ pboard: NSPasteboard, from count: Int, within budget: Duration) async -> Bool {
        let deadline = ContinuousClock.now + budget
        while ContinuousClock.now < deadline {
            if pboard.changeCount != count { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}

nonisolated enum KeyPoster {
    static func post(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// Full-fidelity snapshot - every item, every type - so restoring doesn't
/// downgrade rich clipboard contents (images, RTF) to plain text.
nonisolated struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pboard: NSPasteboard) {
        items = (pboard.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [:]) { $0[$1] = item.data(forType: $1) }
        }
    }

    func restore(to pboard: NSPasteboard) {
        pboard.clearContents()
        pboard.writeObjects(items.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        })
    }
}

nonisolated func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw ProofreadingError.timedOut
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
