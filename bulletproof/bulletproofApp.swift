import SwiftUI

@main
struct BulletproofApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(AppState.shared)
        } label: {
            MenuBarIcon()
        }
        Settings {
            SettingsView()
                .environment(AppState.shared)
        }
    }
}
