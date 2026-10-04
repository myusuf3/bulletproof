import AppKit
import Testing
@testable import bulletproof

@MainActor
private final class FakeDictationSurface: DictationSurface {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("dictation-test-\(UUID().uuidString)"))
    var microphoneStatus: MicrophonePermission.Status = .granted
    var accessibilityTrusted = true
    var frontmostID: pid_t? = 100
    /// What stopRecording hands back - the "audio" the user spoke.
    var recorded: [Float] = []
    var startError: Error?
    /// Simulates the user switching apps while transcription runs.
    var onSleep: () -> Void = {}

    private(set) var requestedMicrophone = false
    private(set) var requestedAccessibility = false
    private(set) var isRecording = false
    private(set) var phases: [DictationOverlayPhase] = []
    private(set) var overlayHidden = false
    private(set) var pastedText: String?
    private(set) var notifications: [String] = []

    func requestMicrophone() async -> Bool {
        requestedMicrophone = true
        return true
    }
    func requestAccessibility() { requestedAccessibility = true }
    func startRecording() throws {
        if let startError { throw startError }
        isRecording = true
    }
    func stopRecording() -> [Float] {
        isRecording = false
        return recorded
    }
    func frontmostAppID() -> pid_t? { frontmostID }
    func heldModifiers() -> NSEvent.ModifierFlags { [] }
    func postPaste() { pastedText = pasteboard.string(forType: .string) }
    func show(_ phase: DictationOverlayPhase) {
        phases.append(phase)
        overlayHidden = false
    }
    func hideOverlay() { overlayHidden = true }
    func notify(title: String, body: String) { notifications.append(title) }
    func sleep(for duration: Duration) async { onSleep() }
}

private struct FakeSpeechEngine: SpeechToTextEngine {
    var result: Result<String, DictationError> = .success("hello world")
    func transcribe(_ samples: [Float]) async throws -> String { try result.get() }
    func prewarm() async {}
}

private struct FakeProofreader: ProofreadingEngine {
    var fails = false
    func proofread(_ text: String) async throws -> String {
        if fails { throw ProofreadingError.timedOut }
        return text.capitalized
    }
}

@MainActor
struct DictationControllerTests {
    private let speech = [Float](repeating: 0.1, count: DictationController.minimumSamples)

    private func makeController(_ surface: FakeDictationSurface,
                                engine: FakeSpeechEngine = FakeSpeechEngine(),
                                proofreader: FakeProofreader? = nil) -> DictationController {
        DictationController(makeEngine: { engine },
                            makeProofreader: { proofreader },
                            shortcutDisplay: { "⌥Space" },
                            surface: surface)
    }

    private func dictate(_ controller: DictationController, _ surface: FakeDictationSurface) async {
        controller.keyDown()
        controller.keyUp()
        // keyUp hands transcription to a Task; wait for it to settle.
        while !controller.isIdle { await Task.yield() }
    }

    @Test func holdThenReleasePastesTheTranscriptAndRestoresTheClipboard() async {
        let surface = FakeDictationSurface()
        surface.recorded = speech
        surface.pasteboard.clearContents()
        surface.pasteboard.setString("user's clipboard", forType: .string)
        let controller = makeController(surface)

        controller.keyDown()
        #expect(surface.isRecording)
        #expect(surface.phases == [.listening])
        controller.keyUp()
        while !controller.isIdle { await Task.yield() }

        #expect(surface.pastedText == "hello world")
        #expect(surface.phases == [.listening, .transcribing])
        #expect(surface.overlayHidden)
        #expect(surface.pasteboard.string(forType: .string) == "user's clipboard")
    }

    @Test func tapTooShortForSpeechShowsAHintAndTypesNothing() async {
        let surface = FakeDictationSurface()
        surface.recorded = [Float](repeating: 0.1, count: DictationController.minimumSamples - 1)
        let controller = makeController(surface)

        await dictate(controller, surface)

        #expect(surface.pastedText == nil)
        #expect(surface.phases.last == .hint("Hold ⌥Space while you speak"))
    }

    @Test func firstPressAsksForTheMicrophoneWithoutRecording() async {
        let surface = FakeDictationSurface()
        surface.microphoneStatus = .notDetermined
        let controller = makeController(surface)

        controller.keyDown()
        await Task.yield()

        #expect(!surface.isRecording)
        #expect(surface.requestedMicrophone)
        #expect(controller.isIdle)
    }

    @Test func deniedMicrophoneExplainsWhereToFixIt() {
        let surface = FakeDictationSurface()
        surface.microphoneStatus = .denied
        let controller = makeController(surface)

        controller.keyDown()

        #expect(!surface.isRecording)
        #expect(surface.notifications == ["Microphone access needed"])
    }

    @Test func missingAccessibilityStopsBeforeListening() {
        // Without it the paste can't land - don't let the user talk for nothing.
        let surface = FakeDictationSurface()
        surface.accessibilityTrusted = false
        let controller = makeController(surface)

        controller.keyDown()

        #expect(!surface.isRecording)
        #expect(surface.requestedAccessibility)
    }

    @Test func releaseWithoutPressDoesNothing() {
        let surface = FakeDictationSurface()
        let controller = makeController(surface)
        controller.keyUp()
        #expect(surface.phases.isEmpty)
    }

    @Test func silenceShowsDidntCatchThat() async {
        let surface = FakeDictationSurface()
        surface.recorded = speech
        let controller = makeController(surface, engine: FakeSpeechEngine(result: .success("  ")))

        await dictate(controller, surface)

        #expect(surface.pastedText == nil)
        guard case .failed = surface.phases.last else {
            Issue.record("expected a failure message, got \(surface.phases)")
            return
        }
    }

    @Test func engineFailureIsShownAndNotified() async {
        let surface = FakeDictationSurface()
        surface.recorded = speech
        let controller = makeController(surface, engine: FakeSpeechEngine(result: .failure(.modelNotInstalled)))

        await dictate(controller, surface)

        #expect(surface.pastedText == nil)
        #expect(surface.phases.last == .failed(DictationError.modelNotInstalled.localizedDescription))
        #expect(surface.notifications == ["Dictation failed"])
    }

    @Test func proofreadingOnPolishesTheTranscript() async {
        let surface = FakeDictationSurface()
        surface.recorded = speech
        let controller = makeController(surface, proofreader: FakeProofreader())

        await dictate(controller, surface)

        #expect(surface.pastedText == "Hello World")
    }

    @Test func failedProofreadStillTypesWhatWasSaid() async {
        let surface = FakeDictationSurface()
        surface.recorded = speech
        let controller = makeController(surface, proofreader: FakeProofreader(fails: true))

        await dictate(controller, surface)

        #expect(surface.pastedText == "hello world")
    }

    @Test func switchingAppsLeavesTheDictationOnTheClipboard() async {
        let surface = FakeDictationSurface()
        surface.recorded = speech
        let controller = makeController(surface)

        controller.keyDown()
        surface.frontmostID = 200
        controller.keyUp()
        while !controller.isIdle { await Task.yield() }

        #expect(surface.pastedText == nil)
        #expect(surface.pasteboard.string(forType: .string) == "hello world")
        #expect(surface.notifications == ["App changed while transcribing"])
    }

    @Test func copyDuringTheSettleWindowIsNotOverwritten() async {
        let surface = FakeDictationSurface()
        surface.recorded = speech
        surface.onSleep = {
            surface.pasteboard.clearContents()
            surface.pasteboard.setString("copied meanwhile", forType: .string)
        }
        let controller = makeController(surface)

        await dictate(controller, surface)

        #expect(surface.pasteboard.string(forType: .string) == "copied meanwhile")
    }

    @Test func microphoneFailureShowsInTheOverlay() {
        let surface = FakeDictationSurface()
        surface.startError = DictationError.noMicrophone
        let controller = makeController(surface)

        controller.keyDown()

        #expect(surface.phases == [.failed(DictationError.noMicrophone.localizedDescription)])
        #expect(controller.isIdle)
    }
}
