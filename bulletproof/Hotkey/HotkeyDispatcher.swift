import AppKit

nonisolated enum HotkeyRoute {
    case ignored, practice, global
}

/// The app's global shortcuts. Each owns its own Carbon registration.
nonisolated enum HotkeySlot: CaseIterable {
    case proofread, dictation

    var title: String {
        switch self {
        case .proofread: "Proofread selection"
        case .dictation: "Dictation"
        }
    }
}

/// Routes hot key presses to the right consumer. RegisterEventHotKey consumes
/// the chord's keyDown, so the onboarding practice step can never see it via a
/// local event monitor - chord completion must arrive through here.
@MainActor final class HotkeyDispatcher {
    static let shared = HotkeyDispatcher()

    private let manager = HotkeyManager(id: 1)
    private let dictationManager = HotkeyManager(id: 2)
    /// Injectable so tests can observe the registration-failure notification.
    var notifier = UserNotifier()
    private lazy var proofreader = SelectionProofreader(
        makeEngine: { AppState.shared.makeEngine() },
        shortcutDisplay: { AppState.shared.shortcut.displayString },
        engineLabel: { AppState.shared.engineChoice.telemetryLabel },
        surface: SystemSurface()
    )
    private let dictationRecorder = AudioRecorder()
    private lazy var dictation = DictationController(
        makeEngine: { AppState.shared.makeSpeechEngine() },
        makeProofreader: {
            // Transcription slips aren't the user's typos - keep them out
            // of the practice drill. Transcripts need punctuation and
            // capitals that typed casual text must not get.
            AppState.shared.proofreadDictation
                ? AppState.shared.makeEngine(recordsStats: false,
                                             instructions: ProofreadPrompt.dictationInstructions)
                : nil
        },
        shortcutDisplay: { AppState.shared.dictationShortcut.displayString },
        surface: SystemDictationSurface(recorder: dictationRecorder,
                                        deviceUID: { AppState.shared.microphoneUID }),
        engineLabel: { AppState.shared.engineChoice.telemetryLabel }
    )

    /// Set by the onboarding practice step while visible. While installed and
    /// our app is frontmost, EVERY press routes to practice - falling through
    /// to the real CGEvent flow would post synthetic keystrokes into the
    /// onboarding window.
    var practiceHandler: (() -> Void)?

    /// The recorder suspends dispatch so pressing the current shortcut while
    /// re-recording it doesn't trigger a proofread.
    var isSuspended = false

    func start() {
        manager.onHotkey = { [weak self] in self?.dispatch() }
        dictationManager.onHotkey = { [weak self] in
            guard let self, !isSuspended else { return }
            dictation.keyDown()
        }
        // Never suspended: a release must always end a recording it started.
        dictationManager.onRelease = { [weak self] in self?.dictation.keyUp() }
        registerOrNotify(AppState.shared.shortcut)
        registerOrNotify(AppState.shared.dictationShortcut, for: .dictation)
    }

    @discardableResult
    func register(_ combo: KeyCombo, for slot: HotkeySlot = .proofread) -> Bool {
        managerFor(slot).register(combo)
    }

    /// Registration is exclusive, so a chord claimed by another app since the
    /// last launch is refused - and the shortcut would silently never fire.
    func registerOrNotify(_ combo: KeyCombo, for slot: HotkeySlot = .proofread) {
        if !register(combo, for: slot) {
            notifier.post(title: "Shortcut unavailable",
                          body: Self.registrationFailureBody(for: combo))
        }
    }

    func combo(for slot: HotkeySlot) -> KeyCombo {
        switch slot {
        case .proofread: AppState.shared.shortcut
        case .dictation: AppState.shared.dictationShortcut
        }
    }

    private func managerFor(_ slot: HotkeySlot) -> HotkeyManager {
        switch slot {
        case .proofread: manager
        case .dictation: dictationManager
        }
    }

    nonisolated static func registrationFailureBody(for combo: KeyCombo) -> String {
        "Another app is using \(combo.displayString). Choose a different shortcut in bulletproof's settings."
    }

    func unregister(_ slot: HotkeySlot = .proofread) {
        managerFor(slot).unregister()
    }

    nonisolated static func route(isSuspended: Bool, appIsActive: Bool,
                                  hasPracticeHandler: Bool) -> HotkeyRoute {
        if isSuspended { return .ignored }
        if appIsActive && hasPracticeHandler { return .practice }
        return .global
    }

    private func dispatch() {
        switch Self.route(isSuspended: isSuspended,
                          appIsActive: NSApp.isActive,
                          hasPracticeHandler: practiceHandler != nil) {
        case .ignored:
            return
        case .practice:
            practiceHandler?()
        case .global:
            proofreader.run()
        }
    }
}
