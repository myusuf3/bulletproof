import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "com.mahdiyusuf.bulletproof", category: "launch")
    private var serviceProvider: ProofreadServiceProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.logger.info("didFinishLaunching, hasSeenOnboarding=\(AppState.shared.hasSeenOnboarding)")
        let provider = ProofreadServiceProvider(appState: AppState.shared)
        serviceProvider = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()
        HotkeyDispatcher.shared.start()
        UserNotifier.requestAuthorizationAtLaunch()
        if !AppState.shared.hasSeenOnboarding {
            OnboardingWindowController.shared.show()
            Self.logger.info("onboarding show() called")
        }
    }
}
