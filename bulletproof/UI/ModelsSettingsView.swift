import SwiftUI

struct ModelsSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var confirmingDeleteAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard {
                ForEach(Array(ModelCatalog.all.enumerated()), id: \.element.id) { index, model in
                    if index > 0 {
                        SettingDivider()
                    }
                    ModelRow(model: model, manager: appState.downloads)
                }
            }

            let orphans = ModelCatalog.orphanIDs(installed: appState.downloads.installedModelIDs)
            if !orphans.isEmpty {
                SettingsCard(header: "No longer offered") {
                    ForEach(Array(orphans.enumerated()), id: \.element) { index, id in
                        if index > 0 {
                            SettingDivider()
                        }
                        OrphanRow(id: id, manager: appState.downloads, store: appState.store)
                    }
                }
            }

            SettingsCard(header: "Storage") {
                SettingRow(title: "Models use \(format(appState.downloads.totalInstalledBytes)) on disk",
                           description: appState.store.availableDiskSpace().map { "\(format($0)) available on this volume." }) {
                    if !appState.downloads.installedModelIDs.isEmpty {
                        Button("Delete All Models…", role: .destructive) {
                            confirmingDeleteAll = true
                        }
                    }
                }
            }
        }
        .onAppear { appState.downloads.refresh() }
        .confirmationDialog("Delete all downloaded models?",
                            isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { appState.deleteAllModels() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees \(format(appState.downloads.totalInstalledBytes)) of disk space. If a local model is selected, proofreading switches back to Apple Intelligence. You can download models again anytime.")
        }
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct ModelRow: View {
    let model: CatalogModel
    let manager: ModelDownloadManager
    @State private var confirmingDelete = false

    var body: some View {
        SettingRow(title: model.displayName, description: rowDescription) {
            control
        }
        .help(model.id)
        .confirmationDialog("Delete \(model.displayName)?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { manager.delete(id: model.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees \(format(installedBytes)) of disk space. You can download the model again anytime.")
        }
    }

    private var rowDescription: String {
        if case .failed(let message) = manager.state(of: model) {
            return message
        }
        return model.blurb
    }

    private var installedBytes: Int64 {
        if case .installed(let bytes) = manager.state(of: model) { bytes } else { model.approxDownloadBytes }
    }

    @ViewBuilder
    private var control: some View {
        switch manager.state(of: model) {
        case .notInstalled, .failed:
            Button("Download (\(format(model.approxDownloadBytes)))") {
                manager.download(model)
            }
        case .downloading(let completed, let total):
            HStack(spacing: 8) {
                ProgressView(value: total > 0 ? Double(completed) / Double(total) : 0)
                    .frame(width: 110)
                Text("\(format(completed)) / \(format(total))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button("Cancel") { manager.cancel(model) }
            }
        case .installed(let bytes):
            HStack(spacing: 8) {
                Text("Installed (\(format(bytes)))")
                    .foregroundStyle(.secondary)
                Button("Delete", role: .destructive) { confirmingDelete = true }
            }
        }
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct OrphanRow: View {
    let id: String
    let manager: ModelDownloadManager
    let store: ModelStore
    @State private var confirmingDelete = false

    var body: some View {
        SettingRow(title: id,
                   description: "Removed from the catalog. Delete to reclaim \(ByteCountFormatter.string(fromByteCount: store.sizeOnDisk(of: id), countStyle: .file)).") {
            Button("Delete", role: .destructive) { confirmingDelete = true }
        }
        .confirmationDialog("Delete \(id)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { manager.delete(id: id) }
            Button("Cancel", role: .cancel) {}
        }
    }
}
