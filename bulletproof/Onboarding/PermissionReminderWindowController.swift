import AppKit
import SwiftUI

/// One step of the walkthrough, reused standalone: shown at launch when
/// onboarding is complete but the Accessibility grant is missing - revoked
/// by the user, or invalidated by an app update. Without this window the
/// hotkey just silently stops working.
struct PermissionReminderView: View {
    var body: some View {
        VStack(spacing: 0) {
            AccessibilityStepView()
                .padding(.horizontal, 40)
                .padding(.top, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Spacer()
                Button("Done") { PermissionReminderWindowController.shared.close() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 640, height: 420)
        .onAppear { NSApp.activate() }
        .onExitCommand { PermissionReminderWindowController.shared.close() }
    }
}

@MainActor final class PermissionReminderWindowController {
    static let shared = PermissionReminderWindowController()
    private var window: NSWindow?

    func show() {
        NSApp.activate()
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: PermissionReminderView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "bulletproof needs Accessibility access"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 640, height: 420))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                PermissionReminderWindowController.shared.window = nil
            }
        }
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}
