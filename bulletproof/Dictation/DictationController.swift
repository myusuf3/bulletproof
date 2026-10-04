import AppKit

nonisolated enum DictationOverlayPhase: Equatable {
    case listening
    case transcribing
    /// Brief guidance, e.g. after a tap too short to be speech.
    case hint(String)
    case failed(String)
}

/// The OS surface dictation drives - a seam so the hold-to-talk flow is
/// unit-testable without a microphone or real key posts.
@MainActor protocol DictationSurface {
    var microphoneStatus: MicrophonePermission.Status { get }
    func requestMicrophone() async -> Bool
    var accessibilityTrusted: Bool { get }
    func requestAccessibility()
    func startRecording() throws
    func stopRecording() -> [Float]
    var pasteboard: NSPasteboard { get }
    func frontmostAppID() -> pid_t?
    func heldModifiers() -> NSEvent.ModifierFlags
    func postPaste()
    func show(_ phase: DictationOverlayPhase)
    func hideOverlay()
    func notify(title: String, body: String)
    func sleep(for duration: Duration) async
}

@MainActor struct SystemDictationSurface: DictationSurface {
    private let system = SystemSurface()
    private let recorder: AudioRecorder
    private let deviceUID: () -> String?

    init(recorder: AudioRecorder, deviceUID: @escaping () -> String?) {
        self.recorder = recorder
        self.deviceUID = deviceUID
    }

    var microphoneStatus: MicrophonePermission.Status { MicrophonePermission.status }
    func requestMicrophone() async -> Bool { await MicrophonePermission.request() }
    var accessibilityTrusted: Bool { system.accessibilityTrusted }
    func requestAccessibility() { system.requestAccessibility() }
    func startRecording() throws { try recorder.start(deviceUID: deviceUID(), keepSamples: true) }
    func stopRecording() -> [Float] { recorder.stop() }
    var pasteboard: NSPasteboard { system.pasteboard }
    func frontmostAppID() -> pid_t? { system.frontmostAppID() }
    func heldModifiers() -> NSEvent.ModifierFlags { system.heldModifiers() }
    func postPaste() { system.postPaste() }
    func show(_ phase: DictationOverlayPhase) { DictationOverlayController.shared.show(phase, levels: recorder.levels) }
    func hideOverlay() { DictationOverlayController.shared.hide() }
    func notify(title: String, body: String) { system.notify(title: title, body: body) }
    func sleep(for duration: Duration) async { await system.sleep(for: duration) }
}

/// Hold-to-talk: the shortcut's press starts recording, its release
/// transcribes and pastes the text at the cursor, then puts the user's
/// clipboard back.
@MainActor final class DictationController {
    /// Shorter than this is a tap, not speech.
    nonisolated static let minimumSamples = 16_000 * 3 / 10

    private enum State {
        case idle
        case recording(target: pid_t?, engine: any SpeechToTextEngine)
        case transcribing
    }

    private let makeEngine: () -> any SpeechToTextEngine
    private let makeProofreader: () -> (any ProofreadingEngine)?
    private let shortcutDisplay: () -> String
    private let surface: any DictationSurface
    private var state = State.idle

    init(makeEngine: @escaping () -> any SpeechToTextEngine,
         makeProofreader: @escaping () -> (any ProofreadingEngine)?,
         shortcutDisplay: @escaping () -> String,
         surface: any DictationSurface) {
        self.makeEngine = makeEngine
        self.makeProofreader = makeProofreader
        self.shortcutDisplay = shortcutDisplay
        self.surface = surface
    }

    var isIdle: Bool {
        if case .idle = state { true } else { false }
    }

    func keyDown() {
        guard isIdle else { return }
        guard surface.accessibilityTrusted else {
            surface.requestAccessibility()
            surface.notify(title: "Accessibility access needed",
                           body: DictationError.accessibilityNeeded.localizedDescription)
            return
        }
        switch surface.microphoneStatus {
        case .granted:
            break
        case .notDetermined:
            // The system prompt takes focus mid-hold; dictation starts on
            // the next press once access is granted.
            Task { _ = await surface.requestMicrophone() }
            return
        case .denied:
            surface.notify(title: "Microphone access needed",
                           body: DictationError.microphoneDenied.localizedDescription)
            return
        }

        let engine = makeEngine()
        Task { await engine.prewarm() }
        do {
            try surface.startRecording()
        } catch {
            surface.show(.failed(error.localizedDescription))
            return
        }
        state = .recording(target: surface.frontmostAppID(), engine: engine)
        surface.show(.listening)
    }

    func keyUp() {
        guard case .recording(let target, let engine) = state else { return }
        let samples = surface.stopRecording()
        guard samples.count >= Self.minimumSamples else {
            state = .idle
            surface.show(.hint("Hold \(shortcutDisplay()) while you speak"))
            return
        }
        state = .transcribing
        surface.show(.transcribing)
        Task {
            defer { state = .idle }
            await finish(samples, engine: engine, target: target)
        }
    }

    func finish(_ samples: [Float], engine: any SpeechToTextEngine, target: pid_t?) async {
        let transcript: String
        do {
            transcript = try await engine.transcribe(samples)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            surface.show(.failed(error.localizedDescription))
            surface.notify(title: "Dictation failed", body: error.localizedDescription)
            return
        }
        guard !transcript.isEmpty else {
            surface.show(.failed("Didn't catch that - try speaking closer to the mic."))
            return
        }
        // A failed proofread must never cost the user what they said.
        var text = transcript
        if let proofreader = makeProofreader() {
            text = (try? await proofreader.proofread(transcript)) ?? transcript
        }
        await insert(text, into: target)
    }

    private func insert(_ text: String, into target: pid_t?) async {
        let pboard = surface.pasteboard
        let snapshot = PasteboardSnapshot(pboard)
        pboard.clearContents()
        pboard.setString(text, forType: .string)
        let dictationCount = pboard.changeCount

        // Transcription takes a moment; ⌘V into whatever the user switched
        // to would put their words in the wrong place.
        guard surface.frontmostAppID() == target else {
            surface.hideOverlay()
            surface.notify(title: "App changed while transcribing",
                           body: "Your dictation is on the clipboard - press ⌘V to paste it.")
            return
        }
        await waitForModifierRelease()
        surface.postPaste()
        surface.hideOverlay()
        // Give the target app time to read the paste before restoring.
        await surface.sleep(for: .milliseconds(300))
        if pboard.changeCount == dictationCount {
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
}
