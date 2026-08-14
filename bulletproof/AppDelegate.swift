import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "com.mahdiyusuf.bulletproof", category: "launch")
    private var serviceProvider: ProofreadServiceProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
