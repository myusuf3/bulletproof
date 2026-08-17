import SwiftUI

/// Models pane: a Superwhisper-style library table sitting directly on the
/// window background - icon + name, speed/accuracy segment bars, and a
/// Cloud/Offline column (size + trash when installed, cloud to download).
struct ModelsSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var confirmingDeleteAll = false

    private static let ratingColumnWidth: CGFloat = 110
    private static let statusColumnWidth: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                GridRow {
                    Text("Model name")
                    Text("Speed / Accuracy")
                        .frame(width: Self.ratingColumnWidth, alignment: .leading)
                    Text("Cloud/Offline")
                        .frame(width: Self.statusColumnWidth, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.bottom, 6)

                BuiltInEngineRow(issue: appState.appleIntelligenceIssue,
                                 statusWidth: Self.statusColumnWidth)

                ForEach(ModelCatalog.all) { model in
                    ModelGridRow(model: model, manager: appState.downloads,
                                 statusWidth: Self.statusColumnWidth)
                }

                ForEach(ModelCatalog.orphanIDs(installed: appState.downloads.installedModelIDs), id: \.self) { id in
                    OrphanGridRow(id: id, manager: appState.downloads, store: appState.store,
                                  statusWidth: Self.statusColumnWidth)
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

/// Apple Intelligence is *chosen* in Engine, but users look here to answer
/// "what AI does this app have" - so the built-in engine is listed alongside
/// the downloadable ones, minus the download/delete affordances.
private struct BuiltInEngineRow: View {
    let issue: String?
    let statusWidth: CGFloat

    var body: some View {
        GridRow {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.indigo.gradient)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Intelligence")
                    Text(issue ?? "Built into macOS - nothing to download")
                        .font(.system(size: 11))
                        .foregroundStyle(issue == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                }
            }
            .padding(.leading, 6)

            RatingBars(speed: 5, accuracy: 3)

            HStack(spacing: 8) {
                Text("Built in")
                    .foregroundStyle(.secondary)
                Image(systemName: issue == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(issue == nil ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
                    .font(.title3)
            }
            .frame(width: statusWidth, alignment: .trailing)
        }
        .padding(.vertical, 10)
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
            .frame(width: 30, height: 30)
            .overlay(
                Image(systemName: "cpu")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// Two stacked five-segment bars, each led by an SF Symbol and tinted so
/// the rows read at a glance: blue speedometer = speed, orange target =
/// accuracy (blue/orange stays distinguishable for color-blind users).
private struct RatingBars: View {
    let speed: Int
    let accuracy: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SegmentBar(symbol: "speedometer", tint: .blue, filled: speed)
            SegmentBar(symbol: "target", tint: .orange, filled: accuracy)
        }
        .help("Speed \(speed) of 5, accuracy \(accuracy) of 5")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speed \(speed) of 5, accuracy \(accuracy) of 5")
    }

    private struct SegmentBar: View {
        let symbol: String
        let tint: Color
        let filled: Int

        var body: some View {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 12)
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(index < filled ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary))
                            .frame(width: 13, height: 3)
                    }
                }
            }
        }
    }
}

private struct ModelGridRow: View {
    let model: CatalogModel
    let manager: ModelDownloadManager
    let statusWidth: CGFloat
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
            .padding(.leading, 6)
            .help(model.id)

            RatingBars(speed: model.speed, accuracy: model.accuracy)

            statusCell
                .frame(width: statusWidth, alignment: .trailing)
        }
        .padding(.vertical, 10)
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
    private var statusCell: some View {
        switch manager.state(of: model) {
        case .notInstalled, .failed:
            CircleIconButton(symbol: "cloud", label: "Download \(model.displayName) (\(format(model.approxDownloadBytes)))") {
                manager.download(model)
            }
            .help("Download (\(format(model.approxDownloadBytes)))")
        case .downloading(let completed, let total):
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 3) {
                    ProgressView(value: total > 0 ? Double(completed) / Double(total) : 0)
                        .frame(width: 72)
                    Text("\(format(completed)) / \(format(total))")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                CircleIconButton(symbol: "xmark", label: "Cancel download") {
                    manager.cancel(model)
                }
            }
        case .installed(let bytes):
            HStack(spacing: 8) {
                Text(format(bytes))
                    .monospacedDigit()
                CircleIconButton(symbol: "trash", label: "Delete \(model.displayName)") {
                    confirmingDelete = true
                }
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
    let statusWidth: CGFloat
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
            .padding(.leading, 6)

            Text("")

            HStack(spacing: 8) {
                Text(ByteCountFormatter.string(fromByteCount: store.sizeOnDisk(of: id), countStyle: .file))
                    .monospacedDigit()
                CircleIconButton(symbol: "trash", label: "Delete \(id)") {
                    confirmingDelete = true
                }
            }
            .frame(width: statusWidth, alignment: .trailing)
        }
        .padding(.vertical, 10)
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
