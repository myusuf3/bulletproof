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

    @Test func finalizeReplacesExistingInstallWithoutDeleteWindow() throws {
        // Re-downloading over an existing install must never pass through a
        // "removed but not yet moved" state - a crash there strands the new
        // download as .partial, which cleanupPartials() then deletes.
        try makeDirectory("org/model", files: ["config.json": "old"])
        try makeDirectory("org/model.partial", files: ["config.json": "new"])
        try store.finalize("org/model")
        let config = store.directory(for: "org/model").appendingPathComponent("config.json")
        #expect(try String(contentsOf: config, encoding: .utf8) == "new")
        #expect(!FileManager.default.fileExists(atPath: store.partialDirectory(for: "org/model").path))
    }

    @Test func availableDiskSpaceWorksBeforeFirstDownload() {
        // The models root doesn't exist until the first download; disk space
        // must still report (the Settings footer reads it on first launch).
        // Parent missing too - mirrors Application Support/bulletproof/Models
        // before anything is downloaded.
        let virgin = ModelStore(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("never-created-\(UUID().uuidString)/Models", isDirectory: true))
        #expect(virgin.availableDiskSpace() != nil)
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

    @Test @MainActor func deleteAllModelsFallsBackToAppleIntelligence() throws {
        try makeDirectory("mlx-community/model-x", files: ["config.json": "{}"])
        let appState = AppState(store: store, defaults: Self.scratchDefaults())
        appState.engineChoice = .local(modelID: "mlx-community/model-x")
        appState.dictationEngineChoice = .local(modelID: "mlx-community/model-x")
        appState.deleteAllModels()
        #expect(appState.engineChoice == .appleIntelligence)
        #expect(appState.dictationEngineChoice == nil)
        #expect(store.installedModelIDs().isEmpty)
    }

    /// Tests run inside bulletproof.app, so writing UserDefaults.standard here
    /// used to overwrite the real app's engine and speech settings.
    @Test @MainActor func appStatePersistsOnlyToItsOwnDefaults() {
        let defaults = Self.scratchDefaults()
        let before = UserDefaults.standard.dictionaryRepresentation()["speechModel"] as? String
        let appState = AppState(store: store, defaults: defaults)
        appState.speechModel = before == SpeechModelChoice.whistle.rawValue ? .appleSpeech : .whistle
        appState.dictationEngineChoice = .appleIntelligence

        #expect(defaults.string(forKey: "speechModel") == appState.speechModel.rawValue)
        #expect(defaults.data(forKey: "dictationEngineChoice") != nil)
        #expect(UserDefaults.standard.string(forKey: "speechModel") == before)
        #expect(AppState(store: store, defaults: defaults).dictationEngineChoice == .appleIntelligence)
    }

    @Test @MainActor func sharedStateUsesScratchDefaultsUnderTheTestHost() {
        let before = UserDefaults.standard.object(forKey: "playSoundOnFix") as? Bool
        AppState.shared.playSoundOnFix.toggle()
        defer { AppState.shared.playSoundOnFix.toggle() }
        #expect(UserDefaults.standard.object(forKey: "playSoundOnFix") as? Bool == before)
        #expect(UserDefaults(suiteName: AppState.testDefaultsSuite)!.object(forKey: "playSoundOnFix") as? Bool
                == AppState.shared.playSoundOnFix)
    }

    private static func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ModelStoreTests-\(UUID().uuidString)")!
    }
}
