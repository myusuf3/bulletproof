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
}
