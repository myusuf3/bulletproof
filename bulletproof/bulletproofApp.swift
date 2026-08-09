import SwiftUI

@main
struct BulletproofApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("bulletproof", systemImage: "checkmark.seal") {
            MenuBarView()
                .environment(AppState.shared)
        }
        Settings {
            SettingsView()
                .environment(AppState.shared)
        }
    }
}
