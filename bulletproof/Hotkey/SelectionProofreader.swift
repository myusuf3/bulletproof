import AppKit
import Carbon.HIToolbox

/// The OS surface the hotkey flow drives - a seam so the orchestration
/// (ordering, restore-on-failure, notifications) is unit-testable without
/// posting real events.
@MainActor protocol ProofreadingSurface {
    var pasteboard: NSPasteboard { get }
    var accessibilityTrusted: Bool { get }
    func requestAccessibility()
    func heldModifiers() -> NSEvent.ModifierFlags
    func postCopy()
    func postPaste()
    func selectionRect() -> NSRect?
    func showSuccess(over rect: NSRect?)
    func notify(title: String, body: String)
    func sleep(for duration: Duration) async
}

@MainActor struct SystemSurface: ProofreadingSurface {
    private let notifier = UserNotifier()

    var pasteboard: NSPasteboard { .general }
    var accessibilityTrusted: Bool { AccessibilityPermission.isTrusted }

    func requestAccessibility() {
        AccessibilityPermission.requestWithPrompt()
    }

    func heldModifiers() -> NSEvent.ModifierFlags {
        NSEvent.modifierFlags.intersection([.command, .shift, .option, .control])
    }

    func postCopy() {
        KeyPoster.post(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
    }

    func postPaste() {
        KeyPoster.post(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }

    func selectionRect() -> NSRect? {
        SelectionLocator.selectionScreenRect()
    }

    func showSuccess(over rect: NSRect?) {
        if let rect {
            SuccessFlashController.shared.flash(over: rect)
        } else {
            SuccessFlashController.shared.flashChip(near: NSEvent.mouseLocation)
        }
    }

    func notify(title: String, body: String) {
        notifier.post(title: title, body: body)
    }

    func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}

/// The global hotkey flow: copy the frontmost app's selection with a synthetic
/// ⌘C, proofread it, paste the correction with ⌘V, and put the user's original
/// clipboard back.
@MainActor final class SelectionProofreader {
    private let makeEngine: () -> any ProofreadingEngine
    private let shortcutDisplay: () -> String
    private let surface: any ProofreadingSurface
    private let engineTimeout: TimeInterval
    private var isRunning = false

    init(makeEngine: @escaping () -> any ProofreadingEngine,
         shortcutDisplay: @escaping () -> String,
         surface: any ProofreadingSurface,
         engineTimeout: TimeInterval = 55) {
        self.makeEngine = makeEngine
        self.shortcutDisplay = shortcutDisplay
        self.surface = surface
        self.engineTimeout = engineTimeout
    }

    func run() {
        guard surface.accessibilityTrusted else {
            surface.requestAccessibility()
            surface.notify(title: "Accessibility access needed",
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

    func performFlow() async {
        let pboard = surface.pasteboard
        let snapshot = PasteboardSnapshot(pboard)
        let countBefore = pboard.changeCount

        // Wait for the user's physical chord to be released - a still-held
        // modifier can combine with the synthetic keystroke in the target app.
        await waitForModifierRelease()
        await surface.sleep(for: .milliseconds(50))
        surface.postCopy()

        guard await changed(pboard, from: countBefore, within: .seconds(1)) else {
            surface.notify(title: "Nothing to proofread",
                           body: "Select some text first, then press \(shortcutDisplay()).")
            return
        }
        guard let text = pboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            surface.notify(title: "Nothing to proofread",
                           body: ProofreadingError.emptyInput.localizedDescription)
            snapshot.restore(to: pboard)
            return
        }

        let engine = makeEngine()
        let timeout = engineTimeout
        let corrected: String
        do {
            corrected = try await withTimeout(seconds: timeout) { try await engine.proofread(text) }
        } catch {
            surface.notify(title: "Proofread failed", body: error.localizedDescription)
            snapshot.restore(to: pboard)
            return
        }

        // Read the selection bounds before ⌘V collapses the selection - the
        // corrected text lands exactly where the original sits.
        let flashRect = surface.selectionRect()

        pboard.clearContents()
        pboard.setString(corrected, forType: .string)
        surface.postPaste()

        // Give the target app time to read the paste before restoring.
        await surface.sleep(for: .milliseconds(300))
        surface.showSuccess(over: flashRect)
        snapshot.restore(to: pboard)
    }

    private func waitForModifierRelease(budget: Duration = .seconds(1)) async {
        let deadline = ContinuousClock.now + budget
        while ContinuousClock.now < deadline {
            if surface.heldModifiers().isEmpty { return }
            await surface.sleep(for: .milliseconds(20))
        }
    }

    private func changed(_ pboard: NSPasteboard, from count: Int, within budget: Duration) async -> Bool {
        let deadline = ContinuousClock.now + budget
        while ContinuousClock.now < deadline {
            if pboard.changeCount != count { return true }
            await surface.sleep(for: .milliseconds(50))
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
