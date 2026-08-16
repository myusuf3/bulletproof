import AppKit

nonisolated enum HotkeyRoute {
    case ignored, practice, global
}

/// Routes hot key presses to the right consumer. RegisterEventHotKey consumes
/// the chord's keyDown, so the onboarding practice step can never see it via a
/// local event monitor - chord completion must arrive through here.
@MainActor final class HotkeyDispatcher {
    static let shared = HotkeyDispatcher()

    private let manager = HotkeyManager()
    /// Injectable so tests can observe the registration-failure notification.
    var notifier = UserNotifier()
    private lazy var proofreader = SelectionProofreader(
        makeEngine: { AppState.shared.makeEngine() },
        shortcutDisplay: { AppState.shared.shortcut.displayString },
        engineLabel: { AppState.shared.engineChoice.telemetryLabel },
        surface: SystemSurface()
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
        registerOrNotify(AppState.shared.shortcut)
    }

    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        manager.register(combo)
    }

    /// Registration is exclusive, so a chord claimed by another app since the
    /// last launch is refused - and the shortcut would silently never fire.
    func registerOrNotify(_ combo: KeyCombo) {
        if !register(combo) {
            notifier.post(title: "Shortcut unavailable",
                          body: Self.registrationFailureBody(for: combo))
        }
    }

    nonisolated static func registrationFailureBody(for combo: KeyCombo) -> String {
        "Another app is using \(combo.displayString). Choose a different shortcut in bulletproof's settings."
    }

    func unregister() {
        manager.unregister()
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
