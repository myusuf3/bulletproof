import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(engineStatus)
        Text("Proofread selection: \(appState.shortcut.displayString)")
        Divider()
        Button("How to Use bulletproof…") {
            OnboardingWindowController.shared.show()
        }
        Button("Check for Updates…") {
            UpdaterController.shared.checkForUpdates()
        }
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("Quit bulletproof") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var engineStatus: String {
        switch appState.engineChoice {
        case .appleIntelligence:
            if let issue = appState.appleIntelligenceIssue {
                "Apple Intelligence: \(issue)"
            } else {
                "Engine: Apple Intelligence"
            }
        case .local(let modelID):
            "Engine: \(ModelCatalog.displayName(for: modelID)) - not active yet"
        }
    }
}
