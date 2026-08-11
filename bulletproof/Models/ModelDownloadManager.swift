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
    let store: ModelStore
    private let client: HuggingFaceClient
    private var tasks: [String: Task<Void, Never>] = [:]

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

    var totalInstalledBytes: Int64 {
        states.values.reduce(0) {
            if case .installed(let bytes) = $1 { $0 + bytes } else { $0 }
        }
    }

    func state(of model: CatalogModel) -> ModelState {
        states[model.id] ?? .notInstalled
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
        } catch {
            states[id] = .failed("Couldn't delete: \(error.localizedDescription)")
        }
    }

    private func runDownload(_ model: CatalogModel) async {
        let store = store
        let partial = store.partialDirectory(for: model.id)
        do {
            let files = try await client.listFiles(repo: model.id)
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
                let download = FileDownload(
                    destination: partial.appendingPathComponent(file.rfilename),
                    onBytesWritten: { throttle.update($0) }
                )
                try await download.run(from: HuggingFaceClient.downloadURL(repo: model.id, file: file.rfilename))
                completedBytes += file.size ?? 0
                states[model.id] = .downloading(completedBytes: completedBytes, totalBytes: totalBytes)
            }

            // A cancel during the last file's download must never install.
            try Task.checkCancellation()
            try store.finalize(model.id)
            states[model.id] = .installed(bytes: store.sizeOnDisk(of: model.id))
        } catch {
            try? FileManager.default.removeItem(at: partial)
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                states[model.id] = .notInstalled
            } else {
                states[model.id] = .failed(error.localizedDescription)
            }
        }
    }
}
