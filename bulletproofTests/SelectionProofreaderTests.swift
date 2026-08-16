import AppKit
import Testing
@testable import bulletproof

/// Scriptable stand-in for the OS: a real (private) pasteboard plus recorded
/// key posts, notifications, and flashes.
@MainActor
private final class FakeSurface: ProofreadingSurface {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("proofreader-test-\(UUID().uuidString)"))
    var trusted = true
    /// What the target app "does" when it receives the synthetic ⌘C.
    var onCopy: (NSPasteboard) -> Void = { _ in }
    /// Simulates the user switching apps mid-flow.
    var frontmostID: pid_t? = 100
    /// Simulates focus sitting in a secure field or terminal.
    var blockReason: FocusGuard.BlockReason?
    /// Simulates what the AX selection read returns (nil = host exposes nothing).
    var selectionText: String?
    /// Called with the running sleep count - lets tests script late events.
    var onSleep: (Int) -> Void = { _ in }

    private(set) var requestedAccessibility = false
    private(set) var copyCount = 0
    private(set) var pasteCount = 0
    private(set) var pastedText: String?
    private(set) var notifications: [(title: String, body: String)] = []
    private(set) var flashed = false
    private(set) var sleepCount = 0
    private(set) var activityEvents: [String] = []
    private(set) var recordedEvents: [ProofreadEvent] = []

    var accessibilityTrusted: Bool { trusted }
    func requestAccessibility() { requestedAccessibility = true }
    func heldModifiers() -> NSEvent.ModifierFlags { [] }
    func frontmostAppID() -> pid_t? { frontmostID }
    func focusBlockReason() -> FocusGuard.BlockReason? { blockReason }
    func readSelection() -> String? { selectionText }
    func postCopy() {
        copyCount += 1
        onCopy(pasteboard)
    }
    func postPaste() {
        pasteCount += 1
        pastedText = pasteboard.string(forType: .string)
    }
    func selectionRect() -> NSRect? { nil }
    func showSuccess(over rect: NSRect?) { flashed = true }
    func notify(title: String, body: String) { notifications.append((title, body)) }
    func recordTelemetry(_ event: ProofreadEvent) { recordedEvents.append(event) }
    func activityBegan() { activityEvents.append("began") }
    func activityEnded(success: Bool) { activityEvents.append(success ? "ended-success" : "ended-failure") }
    func sleep(for duration: Duration) async {
        sleepCount += 1
        onSleep(sleepCount)
    }
}

private final class PrewarmCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}

private struct StubEngine: ProofreadingEngine {
    var result: Result<String, ProofreadingError>
    var delay: Duration = .zero
    var prewarms = PrewarmCounter()

    func proofread(_ text: String) async throws -> String {
        try await Task.sleep(for: delay)
        return try result.get()
    }

    func prewarm() async {
        prewarms.increment()
    }
}

@MainActor
struct SelectionProofreaderTests {
    private let surface = FakeSurface()

    private func makeProofreader(engine: StubEngine,
                                 timeout: TimeInterval = 55,
                                 copyTimeout: TimeInterval = 0.3) -> SelectionProofreader {
        SelectionProofreader(makeEngine: { engine },
                             shortcutDisplay: { "⇧⌘P" },
                             engineLabel: { "appleIntelligence" },
                             surface: surface,
                             engineTimeout: timeout,
                             copyTimeout: copyTimeout)
    }

    @Test func missingAccessibilityPromptsAndStops() {
        surface.trusted = false
        let proofreader = makeProofreader(engine: StubEngine(result: .success("unused")))
        proofreader.run()
        #expect(surface.requestedAccessibility)
        #expect(surface.notifications.count == 1)
        #expect(surface.copyCount == 0)
    }

    @Test func noSelectionNotifiesAndLeavesPasteboardAlone() async {
        surface.pasteboard.clearContents()
        surface.pasteboard.setString("user clipboard", forType: .string)
        // Target app ignores the ⌘C: changeCount never moves.
        let proofreader = makeProofreader(engine: StubEngine(result: .success("unused")))
        await proofreader.performFlow()
        #expect(surface.notifications.first?.title == "Nothing to proofread")
        #expect(surface.pasteCount == 0)
        #expect(surface.pasteboard.string(forType: .string) == "user clipboard")
    }

    @Test func whitespaceSelectionRestoresClipboard() async {
        surface.pasteboard.clearContents()
        surface.pasteboard.setString("user clipboard", forType: .string)
        surface.onCopy = { $0.clearContents(); $0.setString("  \n ", forType: .string) }
        let proofreader = makeProofreader(engine: StubEngine(result: .success("unused")))
        await proofreader.performFlow()
        #expect(surface.notifications.first?.title == "Nothing to proofread")
        #expect(surface.pasteCount == 0)
        #expect(surface.pasteboard.string(forType: .string) == "user clipboard")
    }

    @Test func engineFailureNotifiesRestoresAndNeverPastes() async {
        surface.pasteboard.clearContents()
        surface.pasteboard.setString("user clipboard", forType: .string)
        surface.onCopy = { $0.clearContents(); $0.setString("teh cat", forType: .string) }
        let proofreader = makeProofreader(engine: StubEngine(result: .failure(.notImplemented("stub"))))
        await proofreader.performFlow()
        #expect(surface.notifications.first?.title == "Proofread failed")
        #expect(surface.pasteCount == 0)
        #expect(surface.pasteboard.string(forType: .string) == "user clipboard")
    }

    @Test func successPastesCorrectionThenRestoresClipboard() async {
        surface.pasteboard.clearContents()
        surface.pasteboard.setString("user clipboard", forType: .string)
        surface.onCopy = { $0.clearContents(); $0.setString("teh cat", forType: .string) }
        let proofreader = makeProofreader(engine: StubEngine(result: .success("the cat")))
        await proofreader.performFlow()
        #expect(surface.pasteCount == 1)
        #expect(surface.pastedText == "the cat")
        #expect(surface.flashed)
        #expect(surface.notifications.isEmpty)
        #expect(surface.pasteboard.string(forType: .string) == "user clipboard")
        #expect(surface.activityEvents == ["began", "ended-success"])
    }

    @Test func failureReportsActivityAsFailed() async {
        surface.pasteboard.clearContents()
        surface.pasteboard.setString("user clipboard", forType: .string)
        surface.onCopy = { $0.clearContents(); $0.setString("teh cat", forType: .string) }
        let proofreader = makeProofreader(engine: StubEngine(result: .failure(.notImplemented("stub"))))
        await proofreader.performFlow()
        #expect(surface.activityEvents == ["began", "ended-failure"])
    }

    @Test func copyDuringSettleWindowIsNotClobberedByRestore() async {
        surface.pasteboard.clearContents()
        surface.pasteboard.setString("user clipboard", forType: .string)
        surface.onCopy = { $0.clearContents(); $0.setString("teh cat", forType: .string) }
        // User hits ⌘C in the settle window between paste and restore.
        surface.onSleep = { [weak surface] _ in
            guard let surface, surface.pasteCount == 1 else { return }
            surface.pasteboard.clearContents()
            surface.pasteboard.setString("fresh user copy", forType: .string)
        }
        let proofreader = makeProofreader(engine: StubEngine(result: .success("the cat")))
        await proofreader.performFlow()
        #expect(surface.pastedText == "the cat")
        #expect(surface.pasteboard.string(forType: .string) == "fresh user copy")
    }

    @Test func appSwitchMidFlowAbortsPasteAndLeavesCorrectionOnClipboard() async {
        surface.pasteboard.clearContents()
        surface.pasteboard.setString("user clipboard", forType: .string)
        surface.onCopy = { [weak surface] pboard in
            pboard.clearContents()
            pboard.setString("teh cat", forType: .string)
            // User switches apps while the model is thinking.
            surface?.frontmostID = 200
        }
        let proofreader = makeProofreader(engine: StubEngine(result: .success("the cat")))
        await proofreader.performFlow()
        #expect(surface.pasteCount == 0)
        #expect(surface.notifications.count == 1)
        #expect(surface.notifications.first?.body.contains("clipboard") == true)
        // The correction is deliberately left on the clipboard so it isn't lost.
        #expect(surface.pasteboard.string(forType: .string) == "the cat")
    }

    @Test func slowCopyWithinBudgetStillSucceeds() async {
        surface.pasteboard.clearContents()
        surface.pasteboard.setString("user clipboard", forType: .string)
        // The target app services ⌘C late - a few poll ticks after posting.
        surface.onSleep = { [weak surface] count in
            if count == 3 {
                surface?.pasteboard.clearContents()
                surface?.pasteboard.setString("teh cat", forType: .string)
            }
        }
        let proofreader = makeProofreader(engine: StubEngine(result: .success("the cat")), copyTimeout: 1)
        await proofreader.performFlow()
        #expect(surface.pasteCount == 1)
        #expect(surface.pastedText == "the cat")
    }

    @Test func defaultCopyBudgetCoversSlowElectronApps() {
        #expect(SelectionProofreader.defaultCopyTimeout == 3)
    }

    @Test func successRecordsAppliedEventWithPhases() async {
        surface.pasteboard.clearContents()
        surface.pasteboard.setString("user clipboard", forType: .string)
        surface.onCopy = { $0.clearContents(); $0.setString("teh cat", forType: .string) }
        let proofreader = makeProofreader(engine: StubEngine(result: .success("the cat")))
        await proofreader.performFlow()
        #expect(surface.recordedEvents.count == 1)
        let event = surface.recordedEvents.first
        #expect(event?.entryPoint == .hotkey)
        #expect(event?.outcome == .applied)
        #expect(event?.inputChars == 7)
        #expect(event?.outputChars == 7)
        #expect(event?.phases.map(\.name) == ["read", "engine", "paste"])
    }

    @Test func identicalCorrectionRecordsUnchanged() async {
        surface.pasteboard.clearContents()
        surface.pasteboard.setString("user clipboard", forType: .string)
        surface.onCopy = { $0.clearContents(); $0.setString("the cat", forType: .string) }
        let proofreader = makeProofreader(engine: StubEngine(result: .success("the cat")))
        await proofreader.performFlow()
        #expect(surface.recordedEvents.first?.outcome == .unchanged)
    }

    @Test func gateRejectionRecordsTheReason() async {
        surface.pasteboard.clearContents()
        surface.pasteboard.setString("user clipboard", forType: .string)
        surface.onCopy = { $0.clearContents(); $0.setString("teh cat", forType: .string) }
        let proofreader = makeProofreader(
            engine: StubEngine(result: .failure(.unusableOutput(.emptyOutput))))
        await proofreader.performFlow()
        #expect(surface.recordedEvents.first?.outcome == .gateRejected("emptyOutput"))
    }

    @Test func blockedFocusRecordsAbortedEvent() async {
        surface.blockReason = .secureField
        let proofreader = makeProofreader(engine: StubEngine(result: .success("unused")))
        await proofreader.performFlow()
        #expect(surface.recordedEvents.first?.outcome == .aborted("secure-field"))
        #expect(surface.recordedEvents.first?.inputChars == 0)
    }

    @Test func axSelectionReadSkipsSyntheticCopyEntirely() async {
        surface.pasteboard.clearContents()
        surface.pasteboard.setString("user clipboard", forType: .string)
        surface.selectionText = "teh cat"
        let proofreader = makeProofreader(engine: StubEngine(result: .success("the cat")))
        await proofreader.performFlow()
        // No ⌘C, no pasteboard poll - straight to the engine and the paste.
        #expect(surface.copyCount == 0)
        #expect(surface.pastedText == "the cat")
        #expect(surface.pasteboard.string(forType: .string) == "user clipboard")
        #expect(surface.activityEvents == ["began", "ended-success"])
    }

    @Test func whitespaceAXSelectionFallsBackToSyntheticCopy() async {
        surface.pasteboard.clearContents()
        surface.pasteboard.setString("user clipboard", forType: .string)
        surface.selectionText = "  \n "
        surface.onCopy = { $0.clearContents(); $0.setString("teh cat", forType: .string) }
        let proofreader = makeProofreader(engine: StubEngine(result: .success("the cat")))
        await proofreader.performFlow()
        #expect(surface.copyCount == 1)
        #expect(surface.pastedText == "the cat")
        #expect(surface.pasteboard.string(forType: .string) == "user clipboard")
    }

    @Test func secureFieldFocusRefusesBeforeAnyCopy() async {
        surface.pasteboard.clearContents()
        surface.pasteboard.setString("user clipboard", forType: .string)
        surface.blockReason = .secureField
        let proofreader = makeProofreader(engine: StubEngine(result: .success("unused")))
        await proofreader.performFlow()
        #expect(surface.copyCount == 0)
        #expect(surface.pasteCount == 0)
        #expect(surface.notifications.count == 1)
        #expect(surface.pasteboard.string(forType: .string) == "user clipboard")
        #expect(surface.activityEvents == ["began", "ended-failure"])
    }

    @Test func terminalFocusRefusesBeforeAnyCopy() async {
        surface.blockReason = .terminal
        let proofreader = makeProofreader(engine: StubEngine(result: .success("unused")))
        await proofreader.performFlow()
        #expect(surface.copyCount == 0)
        #expect(surface.notifications.first?.body == FocusGuard.BlockReason.terminal.message)
    }

    @Test func prewarmFiresDuringTheCopyRoundTrip() async {
        surface.pasteboard.clearContents()
        surface.pasteboard.setString("user clipboard", forType: .string)
        surface.onCopy = { $0.clearContents(); $0.setString("teh cat", forType: .string) }
        let engine = StubEngine(result: .success("the cat"))
        let proofreader = makeProofreader(engine: engine)
        await proofreader.performFlow()
        // Prewarm runs in an unstructured task; give it a beat to land.
        for _ in 0..<100 where engine.prewarms.count == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(engine.prewarms.count == 1)
        #expect(surface.pastedText == "the cat")
    }

    @Test func slowEngineTimesOutAndRestores() async {
        surface.pasteboard.clearContents()
        surface.pasteboard.setString("user clipboard", forType: .string)
        surface.onCopy = { $0.clearContents(); $0.setString("teh cat", forType: .string) }
        let proofreader = makeProofreader(engine: StubEngine(result: .success("late"), delay: .seconds(10)),
                                          timeout: 0.2)
        await proofreader.performFlow()
        #expect(surface.notifications.first?.title == "Proofread failed")
        #expect(surface.pasteCount == 0)
        #expect(surface.pasteboard.string(forType: .string) == "user clipboard")
    }
}
