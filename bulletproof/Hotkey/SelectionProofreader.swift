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
    func frontmostAppID() -> pid_t?
    func focusBlockReason() -> FocusGuard.BlockReason?
    func readSelection() -> String?
    func postCopy()
    func postPaste()
    func selectionRect() -> NSRect?
    func showSuccess(over rect: NSRect?)
    func notify(title: String, body: String)
    func activityBegan()
    func activityEnded(success: Bool)
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

    func frontmostAppID() -> pid_t? {
        SelectionReader.focusedAppPid() ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func focusBlockReason() -> FocusGuard.BlockReason? {
        FocusGuard.blockReason()
    }

    func readSelection() -> String? {
        SelectionReader.selectedText()
    }

    func postCopy() {
        post(keyEquivalent: "C", fallbackKey: CGKeyCode(kVK_ANSI_C))
    }

    func postPaste() {
        post(keyEquivalent: "V", fallbackKey: CGKeyCode(kVK_ANSI_V))
    }

    /// Menu press first (immune to held modifiers, localization-proof);
    /// synthetic keystroke only when the host exposes no matching item.
    private func post(keyEquivalent: String, fallbackKey: CGKeyCode) {
        if let pid = frontmostAppID(),
           MenuActionPoster.shared.press(keyEquivalent: keyEquivalent, pid: pid) {
            return
        }
        KeyPoster.post(fallbackKey, flags: .maskCommand)
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

    func activityBegan() {
        AppState.shared.activity.begin()
    }

    func activityEnded(success: Bool) {
        AppState.shared.activity.end(success: success)
    }

    func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}

/// The global hotkey flow: copy the frontmost app's selection with a synthetic
/// ⌘C, proofread it, paste the correction with ⌘V, and put the user's original
/// clipboard back.
@MainActor final class SelectionProofreader {
    /// Electron apps can take well over a second to service a synthetic ⌘C.
    nonisolated static let defaultCopyTimeout: TimeInterval = 3

    private let makeEngine: () -> any ProofreadingEngine
    private let shortcutDisplay: () -> String
    private let surface: any ProofreadingSurface
    private let engineTimeout: TimeInterval
    private let copyTimeout: TimeInterval
    private var isRunning = false

    init(makeEngine: @escaping () -> any ProofreadingEngine,
         shortcutDisplay: @escaping () -> String,
         surface: any ProofreadingSurface,
         engineTimeout: TimeInterval = 55,
         copyTimeout: TimeInterval = SelectionProofreader.defaultCopyTimeout) {
        self.makeEngine = makeEngine
        self.shortcutDisplay = shortcutDisplay
        self.surface = surface
        self.engineTimeout = engineTimeout
        self.copyTimeout = copyTimeout
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
        var succeeded = false
        surface.activityBegan()
        defer { surface.activityEnded(success: succeeded) }

        if let blocked = surface.focusBlockReason() {
            surface.notify(title: "Not proofread", body: blocked.message)
            return
        }

        // The model load takes seconds and the copy round-trip has free
        // wall-clock. Unstructured on purpose: an early flow exit must not
        // cancel a load future requests need.
        let engine = makeEngine()
        Task { await engine.prewarm() }

        let pboard = surface.pasteboard
        let snapshot = PasteboardSnapshot(pboard)

        let text: String
        let copyTargetApp: pid_t?
        if let axText = surface.readSelection(),
           !axText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // AX read: no synthetic ⌘C, no pasteboard poll, no timeout.
            text = axText
            copyTargetApp = surface.frontmostAppID()
        } else {
            let countBefore = pboard.changeCount
            // Wait for the user's physical chord to be released - a still-held
            // modifier can combine with the synthetic keystroke in the target app.
            await waitForModifierRelease()
            await surface.sleep(for: .milliseconds(50))
            copyTargetApp = surface.frontmostAppID()
            surface.postCopy()

            guard await changed(pboard, from: countBefore, within: .seconds(copyTimeout)) else {
                surface.notify(title: "Nothing to proofread",
                               body: "Select some text first, then press \(shortcutDisplay()).")
                return
            }
            guard let copied = pboard.string(forType: .string),
                  !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                surface.notify(title: "Nothing to proofread",
                               body: ProofreadingError.emptyInput.localizedDescription)
                snapshot.restore(to: pboard)
                return
            }
            text = copied
        }

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
        let correctionCount = pboard.changeCount

        // Inference can take many seconds; if the user switched apps in the
        // meantime, ⌘V would paste into the wrong window. Keep the correction
        // on the clipboard instead of pasting blind.
        guard surface.frontmostAppID() == copyTargetApp else {
            surface.notify(title: "App changed during proofreading",
                           body: "The corrected text is on your clipboard - press ⌘V to paste it.")
            return
        }
        surface.postPaste()
        succeeded = true

        // Give the target app time to read the paste before restoring.
        await surface.sleep(for: .milliseconds(300))
        surface.showSuccess(over: flashRect)
        // A ⌘C during the settle window means the clipboard now holds the
        // user's own copy - restoring the snapshot would destroy it.
        if pboard.changeCount == correctionCount {
            snapshot.restore(to: pboard)
        }
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
        // Physically held keys otherwise merge into the synthetic event and
        // strip its ⌘ flag; suppressing local keyboard events plus posting
        // at the annotated session tap keeps the event's own flags intact.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}

/// Full-fidelity snapshot - every item, every type - so restoring doesn't
/// downgrade rich clipboard contents (images, RTF) to plain text.
nonisolated struct PasteboardSnapshot {
    /// Nil means the snapshot itself failed (pasteboardItems returns nil on a
    /// retrieval error) - distinct from a genuinely empty clipboard.
    private let items: [[NSPasteboard.PasteboardType: Data]]?

    init(_ pboard: NSPasteboard) {
        self.init(items: pboard.pasteboardItems.map { boardItems in
            boardItems.map { item in
                item.types.reduce(into: [:]) { $0[$1] = item.data(forType: $1) }
            }
        })
    }

    init(items: [[NSPasteboard.PasteboardType: Data]]?) {
        self.items = items
    }

    func restore(to pboard: NSPasteboard) {
        // Never wipe the clipboard to "restore" a snapshot we never captured.
        guard let items else { return }
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
