import SwiftUI

struct EngineSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard {
                SettingRow(title: "Proofreading engine",
                           description: appState.downloads.installedModelIDs.isEmpty
                               ? "Download a local model in Models to add backup engines."
                               : "Local models run fully on this Mac; the first proofread after switching loads the model.") {
                    if appState.downloads.installedModelIDs.isEmpty {
                        Text("Apple Intelligence")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("", selection: $appState.engineChoice) {
                            Text("Apple Intelligence").tag(EngineChoice.appleIntelligence)
                            ForEach(appState.downloads.installedModelIDs, id: \.self) { id in
                                Text(ModelCatalog.displayName(for: id))
                                    .tag(EngineChoice.local(modelID: id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                }
                SettingDivider()
                SettingRow(title: "Verify corrections",
                           description: appState.downloads.installedModelIDs.isEmpty
                               ? "Double-checks every correction with a local model before pasting. Download a model in Models to enable."
                               : "Double-checks every correction with the local model and blocks edits that don't read right. Experimental.") {
                    Toggle("", isOn: $appState.verifyCorrectionsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(appState.downloads.installedModelIDs.isEmpty)
                }
            }

            SettingsCard(header: "Status") {
                statusRow
                if case .appleIntelligence = appState.engineChoice {
                    SettingDivider()
                    SettingRow(title: "Want higher accuracy?",
                               description: "In bulletproof's proofreading benchmark, the downloadable Qwen3 4B scored 1.00 to Apple Intelligence's 0.84 at similar speed. Apple Intelligence stays the default and uses no extra disk or memory - to switch, download Qwen3 in Models and pick it above.") {
                        EmptyView()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch appState.engineChoice {
        case .appleIntelligence:
            if let issue = appState.appleIntelligenceIssue {
                SettingRow(title: "Apple Intelligence", description: issue) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.title3)
                }
            } else {
                SettingRow(title: "Apple Intelligence",
                           description: "Ready. Corrections run on the system model, on-device.") {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
            }
        case .local(let modelID):
            if appState.store.isInstalled(modelID) {
                SettingRow(title: ModelCatalog.displayName(for: modelID),
                           description: "Runs entirely on this Mac. Unloads after 5 idle minutes to free memory.") {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
            } else {
                SettingRow(title: ModelCatalog.displayName(for: modelID),
                           description: "This model's files are missing. Re-download it in Models, or switch to Apple Intelligence.") {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.title3)
                }
            }
        }
    }
}
