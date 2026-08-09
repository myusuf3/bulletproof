import Foundation
import Testing
@testable import bulletproof

struct ModelStoreTests {
    private let root: URL
    private let store: ModelStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = ModelStore(root: root)
    }

    private func makeDirectory(_ relativePath: String, files: [String: String] = [:]) throws {
        let dir = root.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, contents) in files {
            try Data(contents.utf8).write(to: dir.appendingPathComponent(name))
        }
    }

    @Test func pathsSplitOrgAndName() {
        #expect(store.directory(for: "org/name").path == root.appendingPathComponent("org/name").path)
        #expect(store.partialDirectory(for: "org/name").path == root.appendingPathComponent("org/name.partial").path)
    }

    @Test func installedModelIDsSkipsPartials() throws {
        try makeDirectory("mlx-community/model-a", files: ["config.json": "{}"])
        try makeDirectory("mlx-community/model-b.partial", files: ["config.json": "{}"])
        try makeDirectory("other-org/model-c")
        #expect(store.installedModelIDs() == ["mlx-community/model-a", "other-org/model-c"])
        #expect(store.isInstalled("mlx-community/model-a"))
        #expect(!store.isInstalled("mlx-community/model-b"))
    }

    @Test func finalizePromotesPartial() throws {
        try makeDirectory("org/model.partial", files: ["config.json": "{}"])
        try store.finalize("org/model")
        #expect(store.isInstalled("org/model"))
        #expect(!FileManager.default.fileExists(atPath: store.partialDirectory(for: "org/model").path))
    }

    @Test func cleanupPartialsRemovesOnlyPartials() throws {
        try makeDirectory("org/done", files: ["config.json": "{}"])
        try makeDirectory("org/crashed.partial", files: ["chunk": "data"])
        store.cleanupPartials()
        #expect(store.isInstalled("org/done"))
        #expect(!FileManager.default.fileExists(atPath: store.partialDirectory(for: "org/crashed").path))
    }

    @Test func deleteRemovesModel() throws {
        try makeDirectory("org/model", files: ["config.json": "{}"])
        try store.delete("org/model")
        #expect(!store.isInstalled("org/model"))
        #expect(store.installedModelIDs().isEmpty)
    }

    @Test func sizeOnDiskCountsFiles() throws {
        try makeDirectory("org/model", files: ["a": String(repeating: "x", count: 1000)])
        #expect(store.sizeOnDisk(of: "org/model") >= 1000)
    }
}
