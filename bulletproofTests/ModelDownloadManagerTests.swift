import Foundation
import Testing
@testable import bulletproof

@MainActor
struct ModelDownloadManagerTests {
    private let store: ModelStore
    private let model = CatalogModel(id: "org/model", displayName: "Model", blurb: "x", approxDownloadBytes: 1,
                                     speed: 1, accuracy: 1, revision: "run8-final")

    init() throws {
        store = ModelStore(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelDownloadManagerTests-\(UUID().uuidString)", isDirectory: true))
        let installed = store.directory(for: model.id)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: installed.appendingPathComponent("config.json"))
    }

    private func manager(status: Int) -> ModelDownloadManager {
        var client = HuggingFaceClient()
        client.fetch = { request in
            (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        return ModelDownloadManager(store: store, client: client)
    }

    private func waitForDownload(_ manager: ModelDownloadManager) async throws {
        for _ in 0..<500 {
            guard case .downloading = manager.state(of: model) else { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("download never finished")
    }

    @Test func installWithoutARecordedRevisionOffersAnUpdate() {
        #expect(manager(status: 200).updateAvailable(for: model))
    }

    @Test func failedUpdateKeepsTheInstalledModel() async throws {
        let manager = manager(status: 500)
        manager.download(model)
        try await waitForDownload(manager)
        guard case .installed = manager.state(of: model) else {
            Issue.record("expected the old install to stay usable, got \(manager.state(of: model))")
            return
        }
        #expect(store.isInstalled(model.id))
        #expect(manager.updateError(for: model) != nil)
        #expect(manager.updateAvailable(for: model))
    }
}
