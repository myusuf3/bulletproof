import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            EngineSettingsView()
                .tabItem { Label("Engine", systemImage: "brain") }
                .frame(width: 540)
            ShortcutSettingsView()
                .tabItem { Label("Shortcut", systemImage: "keyboard") }
                .frame(width: 540)
            ModelsSettingsView()
                .tabItem { Label("Models", systemImage: "arrow.down.circle") }
                .frame(width: 540, height: 420)
        }
    }
}
