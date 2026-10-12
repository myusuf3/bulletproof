import Testing
@testable import bulletproof

struct ModelCatalogTests {
    @Test func catalogEntriesAreWellFormed() {
        #expect(!ModelCatalog.all.isEmpty)
        #expect(Set(ModelCatalog.all.map(\.id)).count == ModelCatalog.all.count)
        for model in ModelCatalog.all {
            #expect(model.id.split(separator: "/").count == 2)
            #expect(!model.displayName.isEmpty)
            #expect(!model.blurb.isEmpty)
            #expect(model.approxDownloadBytes > 0)
            #expect((1...5).contains(model.speed))
            #expect((1...5).contains(model.accuracy))
        }
    }

    @Test func orphansAreInstalledModelsNotInCatalog() {
        let installed = [ModelCatalog.all[0].id, "mlx-community/gemma-2-9b-it-4bit"]
        let orphans = ModelCatalog.orphanIDs(installed: installed)
        #expect(orphans == ["mlx-community/gemma-2-9b-it-4bit"])
    }

    @Test func noOrphansWhenAllInstalledAreCataloged() {
        #expect(ModelCatalog.orphanIDs(installed: ModelCatalog.all.map(\.id)).isEmpty)
    }

    @Test func whistleDownloadsOnlyTheRuntimeModel() {
        // The repo also holds a 220 MB training checkpoint nobody needs.
        #expect(ModelCatalog.speech == [ModelCatalog.whistle])
        #expect(ModelCatalog.whistle.files == [ModelCatalog.whistleModelFile])
    }

    @Test func subfolderDownloadsOnlyThatFolderAtTheModelRoot() {
        let model = CatalogModel(id: "org/name", displayName: "x", blurb: "x", approxDownloadBytes: 1,
                                 speed: 1, accuracy: 1, subfolder: "mlx-4bit")
        let listed = [HFFile(rfilename: "config.json", size: 10),
                      HFFile(rfilename: "model-00001-of-00002.safetensors", size: 4_000),
                      HFFile(rfilename: "mlx-4bit/config.json", size: 11),
                      HFFile(rfilename: "mlx-4bit/model.safetensors", size: 2_000),
                      HFFile(rfilename: "adapter/adapter_model.safetensors", size: 100)]
        let plan = model.downloadPlan(listed)
        #expect(plan.map(\.remote) == ["mlx-4bit/config.json", "mlx-4bit/model.safetensors"])
        #expect(plan.map(\.local) == ["config.json", "model.safetensors"])
        #expect(plan.compactMap(\.size).reduce(0, +) == 2_011)
    }

    @Test func withoutSubfolderThePlanIsTheFileFilter() {
        let listed = [HFFile(rfilename: "whistle.cact", size: 5), HFFile(rfilename: "checkpoint.pt", size: 50)]
        #expect(ModelCatalog.whistle.downloadPlan(listed).map(\.local) == ["whistle.cact"])
        let base = ModelCatalog.proofreading.first { $0.id == "mlx-community/Qwen3-4B-Instruct-2507-4bit" }!
        #expect(base.downloadPlan(listed).map(\.local) == ["whistle.cact", "checkpoint.pt"])
    }

    @Test func fineTuneIsListedFirstAndDownloadsItsMLXBuild() {
        #expect(ModelCatalog.proofreading.first?.id == ModelCatalog.recommendedProofreaderID)
        #expect(ModelCatalog.proofreading.first?.subfolder == "mlx-4bit")
    }

    @Test func defaultEngineIsTheFineTuneOnlyWhenInstalled() {
        #expect(AppState.defaultEngineChoice(installed: []) == .appleIntelligence)
        #expect(AppState.defaultEngineChoice(installed: ["mlx-community/Qwen3-4B-Instruct-2507-4bit"]) == .appleIntelligence)
        #expect(AppState.defaultEngineChoice(installed: [ModelCatalog.recommendedProofreaderID])
                == .local(modelID: ModelCatalog.recommendedProofreaderID))
    }

    @Test func downloadingTheFineTuneAdoptsItUnlessTheUserChose() {
        #expect(AppState.shouldAdopt(installedID: ModelCatalog.recommendedProofreaderID, hasSavedChoice: false))
        #expect(!AppState.shouldAdopt(installedID: ModelCatalog.recommendedProofreaderID, hasSavedChoice: true))
        #expect(!AppState.shouldAdopt(installedID: "mlx-community/gemma-3-4b-it-4bit", hasSavedChoice: false))
    }

    @Test func speechModelsNeverOfferThemselvesAsProofreaders() {
        let installed = [ModelCatalog.whistle.id, ModelCatalog.proofreading[0].id, "mlx-community/retired-model"]
        #expect(ModelCatalog.proofreadingIDs(installed: installed)
                == [ModelCatalog.proofreading[0].id, "mlx-community/retired-model"])
        #expect(!ModelCatalog.proofreading.contains(ModelCatalog.whistle))
    }
}
