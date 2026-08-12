import SwiftUI

struct EngineSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                if appState.downloads.installedModelIDs.isEmpty {
                    // A radio group with a single option reads as broken UI;
                    // choices appear once a local model is installed.
                    LabeledContent("Proofreading engine", value: "Apple Intelligence")
                } else {
                    Picker("Proofreading engine", selection: $appState.engineChoice) {
                        Text("Apple Intelligence (recommended)")
                            .tag(EngineChoice.appleIntelligence)
                        ForEach(appState.downloads.installedModelIDs, id: \.self) { id in
                            Text(ModelCatalog.displayName(for: id))
                                .tag(EngineChoice.local(modelID: id))
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
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
                Label {
                    Text(issue)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } else {
                Label {
                    Text("Apple Intelligence is ready.")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        case .local(let modelID):
            if appState.store.isInstalled(modelID) {
                Label {
                    Text("\(ModelCatalog.displayName(for: modelID)) runs entirely on this Mac. The first proofread after switching loads the model and takes a few extra seconds.")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Label {
                    Text("This model's files are missing. Re-download it in the Models tab, or switch to Apple Intelligence.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
