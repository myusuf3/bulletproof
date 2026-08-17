import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "com.mahdiyusuf.bulletproof", category: "launch")
    private var serviceProvider: ProofreadServiceProvider?

    /// The unit-test host must not run launch side effects: registering the
    /// global hotkey, starting Sparkle (network I/O on CI), opening windows,
    /// and requesting notification authorization - the last can throw
    /// NSInternalInconsistencyException in CI's unsigned bundle depending on
    /// LaunchServices timing, killing the host and failing the whole suite
    /// at 0.000s.
    nonisolated static func isTestHost(environment: [String: String]) -> Bool {
        environment["XCTestSessionIdentifier"] != nil
            || environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isTestHost(environment: ProcessInfo.processInfo.environment) else {
            Self.logger.info("didFinishLaunching: test host, skipping launch side effects")
            return
        }
        Self.logger.info("didFinishLaunching, needsOnboarding=\(AppState.shared.onboarding.needsOnboarding)")
        let provider = ProofreadServiceProvider(appState: AppState.shared)
        serviceProvider = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()
        HotkeyDispatcher.shared.start()
        UserNotifier.requestAuthorizationAtLaunch()
        _ = UpdaterController.shared  // start Sparkle's automatic update checks at launch
        if AppState.shared.onboarding.needsOnboarding {
            OnboardingWindowController.shared.show()
            Self.logger.info("onboarding show() called")
        } else if !AccessibilityPermission.isTrusted {
            // The grant was revoked or invalidated by an app update - the
            // hotkey would otherwise just silently stop working.
            PermissionReminderWindowController.shared.show()
            Self.logger.info("accessibility reminder show() called")
        }
    }
}
