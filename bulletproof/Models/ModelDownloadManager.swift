import Foundation
import Observation

@MainActor @Observable
final class ModelDownloadManager {
    enum ModelState: Equatable {
        case notInstalled
        case downloading(completedBytes: Int64, totalBytes: Int64)
        case installed(bytes: Int64)
        case failed(String)
    }

    private(set) var states: [String: ModelState] = [:]
    /// Why the last update of an installed model failed; the old install keeps working.
    private(set) var updateErrors: [String: String] = [:]
    let store: ModelStore
    private let client: HuggingFaceClient
    private var tasks: [String: Task<Void, Never>] = [:]
    /// Called with the repo id after a download installs (AppState adopts the
    /// recommended proofreader this way).
    var onInstalled: ((String) -> Void)?

    init(store: ModelStore, client: HuggingFaceClient = HuggingFaceClient()) {
        self.store = store
        self.client = client
        refresh()
    }

    var installedModelIDs: [String] {
        states.compactMap { id, state in
            if case .installed = state { id } else { nil }
        }.sorted()
    }

    var installedProofreadingModelIDs: [String] {
        ModelCatalog.proofreadingIDs(installed: installedModelIDs)
    }

    var totalInstalledBytes: Int64 {
        states.values.reduce(0) {
            if case .installed(let bytes) = $1 { $0 + bytes } else { $0 }
        }
    }

    func state(of model: CatalogModel) -> ModelState {
        states[model.id] ?? .notInstalled
    }

    func updateAvailable(for model: CatalogModel) -> Bool {
        guard case .installed = state(of: model) else { return false }
        return model.needsUpdate(installedRevision: store.installedRevision(of: model.id))
    }

    func updateError(for model: CatalogModel) -> String? {
        updateErrors[model.id]
    }

    func refresh() {
        var refreshed: [String: ModelState] = [:]
        for id in store.installedModelIDs() {
            refreshed[id] = .installed(bytes: store.sizeOnDisk(of: id))
        }
        for model in ModelCatalog.all where refreshed[model.id] == nil {
            refreshed[model.id] = .notInstalled
        }
        states = refreshed
    }

    func download(_ model: CatalogModel) {
        guard tasks[model.id] == nil else { return }
        updateErrors[model.id] = nil
        states[model.id] = .downloading(completedBytes: 0, totalBytes: model.approxDownloadBytes)
        tasks[model.id] = Task {
            await runDownload(model)
            tasks[model.id] = nil
        }
    }

    func cancel(_ model: CatalogModel) {
        tasks[model.id]?.cancel()
    }

    func delete(id: String) {
        do {
            try store.delete(id)
            states[id] = ModelCatalog.all.contains { $0.id == id } ? .notInstalled : nil
            // A deleted model may be the one currently loaded (targeted, so
            // deleting one model never dumps another that's resident).
            let directory = store.directory(for: id)
            Task { await LocalModelRuntime.shared.evict(directory: directory) }
        } catch {
            states[id] = .failed("Couldn't delete: \(error.localizedDescription)")
        }
    }

    private func runDownload(_ model: CatalogModel) async {
        let store = store
        let partial = store.partialDirectory(for: model.id)
        do {
            let files = model.downloadPlan(try await client.listFiles(repo: model.id, revision: model.revision))
            let totalBytes = files.compactMap(\.size).reduce(0, +)
            try? FileManager.default.removeItem(at: partial)
            try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)

            var completedBytes: Int64 = 0
            for file in files {
                try Task.checkCancellation()
                let base = completedBytes
                let throttle = ByteProgressThrottle { [weak self] written in
                    guard let self else { return }
                    Task { @MainActor in
                        self.states[model.id] = .downloading(completedBytes: base + written, totalBytes: totalBytes)
                    }
                }
                let destination = partial.appendingPathComponent(file.local)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let download = FileDownload(
                    destination: destination,
                    onBytesWritten: { throttle.update($0) }
                )
                try await download.run(from: HuggingFaceClient.downloadURL(repo: model.id, file: file.remote,
                                                                           revision: model.revision))
                if let mismatch = DownloadIntegrity.sizeMismatch(at: destination, expected: file.size) {
                    throw URLError(.cannotWriteToFile, userInfo: [NSLocalizedDescriptionKey: mismatch])
                }
                completedBytes += file.size ?? 0
                states[model.id] = .downloading(completedBytes: completedBytes, totalBytes: totalBytes)
            }

            // A cancel during the last file's download must never install.
            try Task.checkCancellation()
            try store.recordRevision(model.revision, for: model.id)
            try store.finalize(model.id)
            states[model.id] = .installed(bytes: store.sizeOnDisk(of: model.id))
            // An update replaced the files under a model that may be loaded;
            // the next use must load the new weights.
            let directory = store.directory(for: model.id)
            Task { await LocalModelRuntime.shared.evict(directory: directory) }
            onInstalled?(model.id)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            if store.isInstalled(model.id) {
                // A failed or cancelled update leaves the previous install in place and usable.
                states[model.id] = .installed(bytes: store.sizeOnDisk(of: model.id))
                if !cancelled { updateErrors[model.id] = error.localizedDescription }
            } else if cancelled {
                states[model.id] = .notInstalled
            } else {
                states[model.id] = .failed(error.localizedDescription)
            }
        }
    }
}
