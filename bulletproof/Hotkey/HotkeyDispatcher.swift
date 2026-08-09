import AppKit

/// Routes hot key presses to the right consumer. RegisterEventHotKey consumes
/// the chord's keyDown, so the onboarding practice step can never see it via a
/// local event monitor - chord completion must arrive through here.
@MainActor final class HotkeyDispatcher {
    static let shared = HotkeyDispatcher()

    private let manager = HotkeyManager()
    private lazy var proofreader = SelectionProofreader(appState: AppState.shared)

    /// Set by the onboarding practice step while visible; returns true when it
    /// consumed the press. Only consulted while our app is frontmost - a press
    /// with another app focused is always the global flow.
    var practiceHandler: (() -> Bool)?

    /// The recorder suspends dispatch so pressing the current shortcut while
    /// re-recording it doesn't trigger a proofread.
    var isSuspended = false

    func start() {
        manager.onHotkey = { [weak self] in self?.dispatch() }
        register(AppState.shared.shortcut)
    }

    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        manager.register(combo)
    }

    private func dispatch() {
        guard !isSuspended else { return }
        if NSApp.isActive, let practiceHandler, practiceHandler() { return }
        proofreader.run()
    }
}
