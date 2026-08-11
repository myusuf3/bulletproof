import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
                    .frame(width: 560)
            }
            Tab("Engine", systemImage: "brain") {
                EngineSettingsView()
                    .frame(width: 560)
            }
            Tab("Models", systemImage: "arrow.down.circle") {
                ModelsSettingsView()
                    .frame(width: 560, height: 400)
            }
        }
    }
}
