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

    private(set) var requestedAccessibility = false
    private(set) var copyCount = 0
    private(set) var pasteCount = 0
    private(set) var pastedText: String?
    private(set) var notifications: [(title: String, body: String)] = []
    private(set) var flashed = false

    var accessibilityTrusted: Bool { trusted }
    func requestAccessibility() { requestedAccessibility = true }
    func heldModifiers() -> NSEvent.ModifierFlags { [] }
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
    func sleep(for duration: Duration) async {}
}

private struct StubEngine: ProofreadingEngine {
    var result: Result<String, ProofreadingError>
    var delay: Duration = .zero

    func proofread(_ text: String) async throws -> String {
        try await Task.sleep(for: delay)
        return try result.get()
    }
}

@MainActor
struct SelectionProofreaderTests {
    private let surface = FakeSurface()

    private func makeProofreader(engine: StubEngine, timeout: TimeInterval = 55) -> SelectionProofreader {
        SelectionProofreader(makeEngine: { engine },
                             shortcutDisplay: { "⇧⌘P" },
                             surface: surface,
                             engineTimeout: timeout)
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
