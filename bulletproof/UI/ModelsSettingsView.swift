import SwiftUI

struct ModelsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section {
                ForEach(ModelCatalog.all) { model in
                    ModelRow(model: model, manager: appState.downloads)
                }
            } footer: {
                HStack {
                    Text("Models use \(format(appState.downloads.totalInstalledBytes)) on disk")
                    Spacer()
                    if let free = appState.store.availableDiskSpace() {
                        Text("\(format(free)) available")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { appState.downloads.refresh() }
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .failed(let message) = manager.state(of: model) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .help(model.id)
            Spacer()
            control
        }
        .padding(.vertical, 4)
        .confirmationDialog("Delete \(model.displayName)?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { manager.delete(model) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees \(format(installedBytes)) of disk space. You can download the model again anytime.")
        }
    }

    private var subtitle: String {
        switch manager.state(of: model) {
        case .installed:
            "Ready to use as a backup engine"
        default:
            "\(format(model.approxDownloadBytes)) download"
        }
    }

    private var installedBytes: Int64 {
        if case .installed(let bytes) = manager.state(of: model) { bytes } else { model.approxDownloadBytes }
    }

    @ViewBuilder
    private var control: some View {
        switch manager.state(of: model) {
        case .notInstalled, .failed:
            Button("Download") {
                manager.download(model)
            }
        case .downloading(let completed, let total):
            HStack(spacing: 8) {
                ProgressView(value: total > 0 ? Double(completed) / Double(total) : 0)
                    .frame(width: 120)
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
