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
        // A plain Window instead of the Settings scene: Settings windows
        // disable minimize/zoom and restore odd frames under LSUIElement.
        Window("Settings", id: "settings") {
            SettingsView()
                .environment(AppState.shared)
        }
        .defaultSize(width: 940, height: 620)
        .defaultPosition(.center)
    }
}
