import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(engineStatus)
        Text("Proofread selection: \(appState.shortcut.displayString)")
        if appState.history.wordsProofread > 0 {
            Text("\(appState.history.wordsProofread.formatted()) words proofread - all on-device")
        }
        if !appState.history.entries.isEmpty {
            Divider()
            Menu("Recent Corrections") {
                ForEach(appState.history.entries) { entry in
                    Button(CorrectionHistory.menuPreview(entry.corrected)) {
                        let pboard = NSPasteboard.general
                        pboard.clearContents()
                        pboard.setString(entry.corrected, forType: .string)
                    }
                }
                Divider()
                Button("Clear History") {
                    appState.history.clear()
                }
            }
        }
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
            "Engine: \(ModelCatalog.displayName(for: modelID))"
        }
    }
}
