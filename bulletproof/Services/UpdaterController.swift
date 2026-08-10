import Sparkle

/// Owns the single Sparkle updater for the app's lifetime. Sparkle requires
/// its controller to be created once and kept alive, so this mirrors the
/// OnboardingWindowController singleton pattern.
@MainActor final class UpdaterController {
    static let shared = UpdaterController()

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
