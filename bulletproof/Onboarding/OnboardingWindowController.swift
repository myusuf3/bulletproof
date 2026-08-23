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
        // The walkthrough is deliberately dark-glass regardless of system
        // theme, so its controls must render for dark.
        window.appearance = NSAppearance(named: .darkAqua)
        // No traffic lights on the hero card; Esc and the flow's own
        // buttons are the ways out (closable stays in the mask so
        // close()/⌘W keep working).
        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(buttonType)?.isHidden = true
        }
        window.setContentSize(NSSize(width: 640, height: 540))
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
