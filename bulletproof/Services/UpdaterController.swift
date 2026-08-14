#if !BULLETPROOF_DEV
import Sparkle
#endif

/// Owns the single Sparkle updater for the app's lifetime. Sparkle requires
/// its controller to be created once and kept alive, so this mirrors the
/// OnboardingWindowController singleton pattern.
@MainActor final class UpdaterController {
    static let shared = UpdaterController()

    #if !BULLETPROOF_DEV
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
    #else
    // The dev target doesn't link Sparkle at all: a dev build must never
    // pull the prod appcast and replace itself - in any configuration.
    var canCheckForUpdates: Bool { false }
    func checkForUpdates() {}
    #endif
}
