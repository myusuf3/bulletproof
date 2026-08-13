import SwiftUI

/// Models pane: a library table with aligned columns (icon + name, size,
/// action), Superwhisper-style, rather than generic settings rows.
struct ModelsSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var confirmingDeleteAll = false

    private static let sizeColumnWidth: CGFloat = 96
    private static let actionColumnWidth: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
                    GridRow {
                        Text("Model name")
                        Text("Size")
                            .gridColumnAlignment(.trailing)
                        Text("")
                            .frame(width: Self.actionColumnWidth)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    ForEach(ModelCatalog.all) { model in
                        Divider()
                            .gridCellColumns(3)
                            .padding(.leading, 14)
                        ModelGridRow(model: model, manager: appState.downloads,
                                     sizeWidth: Self.sizeColumnWidth,
                                     actionWidth: Self.actionColumnWidth)
                    }

                    ForEach(ModelCatalog.orphanIDs(installed: appState.downloads.installedModelIDs), id: \.self) { id in
                        Divider()
                            .gridCellColumns(3)
                            .padding(.leading, 14)
                        OrphanGridRow(id: id, manager: appState.downloads, store: appState.store,
                                      sizeWidth: Self.sizeColumnWidth,
                                      actionWidth: Self.actionColumnWidth)
                    }
                }
                .padding(.vertical, 2)
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

/// Small rounded-square glyph, one hue per model family.
private struct ModelIcon: View {
    let modelID: String

    private var color: Color {
        modelID.localizedCaseInsensitiveContains("qwen") ? .purple
            : modelID.localizedCaseInsensitiveContains("gemma") ? .blue
            : .gray
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(color.gradient)
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: "cpu")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

private struct ModelGridRow: View {
    let model: CatalogModel
    let manager: ModelDownloadManager
    let sizeWidth: CGFloat
    let actionWidth: CGFloat
    @State private var confirmingDelete = false

    var body: some View {
        GridRow {
            HStack(spacing: 10) {
                ModelIcon(modelID: model.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(isFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
            }
            .padding(.leading, 14)
            .help(model.id)

            sizeCell
                .gridColumnAlignment(.trailing)

            actionCell
                .frame(width: actionWidth)
        }
        .padding(.vertical, 9)
        .confirmationDialog("Delete \(model.displayName)?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { manager.delete(id: model.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees \(format(installedBytes)) of disk space. You can download the model again anytime.")
        }
    }

    private var isFailed: Bool {
        if case .failed = manager.state(of: model) { return true }
        return false
    }

    private var subtitle: String {
        if case .failed(let message) = manager.state(of: model) { return message }
        return model.blurb
    }

    private var installedBytes: Int64 {
        if case .installed(let bytes) = manager.state(of: model) { bytes } else { model.approxDownloadBytes }
    }

    @ViewBuilder
    private var sizeCell: some View {
        switch manager.state(of: model) {
        case .downloading(let completed, let total):
            VStack(alignment: .trailing, spacing: 3) {
                ProgressView(value: total > 0 ? Double(completed) / Double(total) : 0)
                    .frame(width: sizeWidth)
                Text("\(format(completed)) / \(format(total))")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        case .installed(let bytes):
            Text(format(bytes))
                .monospacedDigit()
        case .notInstalled, .failed:
            Text(format(model.approxDownloadBytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionCell: some View {
        switch manager.state(of: model) {
        case .notInstalled, .failed:
            CircleIconButton(symbol: "arrow.down.circle.fill", label: "Download \(model.displayName)") {
                manager.download(model)
            }
        case .downloading:
            CircleIconButton(symbol: "xmark.circle.fill", label: "Cancel download") {
                manager.cancel(model)
            }
        case .installed:
            CircleIconButton(symbol: "trash", label: "Delete \(model.displayName)") {
                confirmingDelete = true
            }
        }
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct OrphanGridRow: View {
    let id: String
    let manager: ModelDownloadManager
    let store: ModelStore
    let sizeWidth: CGFloat
    let actionWidth: CGFloat
    @State private var confirmingDelete = false

    var body: some View {
        GridRow {
            HStack(spacing: 10) {
                ModelIcon(modelID: id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(id)
                    Text("No longer offered - delete to reclaim space")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 14)

            Text(ByteCountFormatter.string(fromByteCount: store.sizeOnDisk(of: id), countStyle: .file))
                .monospacedDigit()
                .gridColumnAlignment(.trailing)

            CircleIconButton(symbol: "trash", label: "Delete \(id)") {
                confirmingDelete = true
            }
            .frame(width: actionWidth)
        }
        .padding(.vertical, 9)
        .confirmationDialog("Delete \(id)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { manager.delete(id: id) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Superwhisper-style circular action: quiet gray circle, dark glyph.
private struct CircleIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: .quinaryLabel))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
