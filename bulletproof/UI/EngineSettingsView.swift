import SwiftUI

struct EngineSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                Picker("Proofreading engine", selection: $appState.engineChoice) {
                    Text("Apple Intelligence (recommended)")
                        .tag(EngineChoice.appleIntelligence)
                    ForEach(appState.downloads.installedModelIDs, id: \.self) { id in
                        Text(ModelCatalog.displayName(for: id))
                            .tag(EngineChoice.local(modelID: id))
                    }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                if appState.downloads.installedModelIDs.isEmpty {
                    Text("Download a local model in the Models tab to add backup engines.")
                }
            }

            Section {
                statusCallout
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusCallout: some View {
        switch appState.engineChoice {
        case .appleIntelligence:
            if let issue = appState.appleIntelligenceIssue {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("Apple Intelligence is ready.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        case .local:
            Label("This model is downloaded, but local inference support is coming in a future update. Proofreading will fail until then - Apple Intelligence is the working engine.",
                  systemImage: "info.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
}
