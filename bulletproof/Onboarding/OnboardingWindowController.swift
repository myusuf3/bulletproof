import AppKit
import SwiftUI

/// Owns the onboarding window directly in AppKit. SwiftUI Window scenes have
/// no reliable way to present at launch from a menu-bar-only app (launch
/// behavior is skipped when saved state exists, and MenuBarExtra labels never
/// receive onAppear), so this controller is the single open/close path.
@MainActor final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show() {
        NSApp.activate()
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: OnboardingView().environment(AppState.shared))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to bulletproof"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 640, height: 480))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                OnboardingWindowController.shared.window = nil
            }
        }
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}
