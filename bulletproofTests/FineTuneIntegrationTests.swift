import Foundation
import Testing
@testable import bulletproof

private var releasedFineTuneInstalled: Bool {
    let id = ModelCatalog.recommendedProofreaderID
    let fineTune = ModelCatalog.all.first { $0.id == id }!
    return ModelStore().isInstalled(id) && !fineTune.needsUpdate(installedRevision: ModelStore().installedRevision(of: id))
}

/// Real-inference checks against the installed fine-tune, with the prompt the
/// app picks for it. Runs only on machines that have the catalog's pinned
/// release downloaded (CI skips - no model there); older snapshots either
/// miss the particle fix or reword the sentence around it.
@Suite(.enabled(if: releasedFineTuneInstalled), .serialized)
struct FineTuneIntegrationTests {
    private static let id = ModelCatalog.recommendedProofreaderID
    private static let engine = LocalModelEngine(
        modelDirectory: ModelStore().directory(for: id),
        instructions: AppState.typedInstructions(modelID: id, installedRevision: ModelStore().installedRevision(of: id)))

    @Test func fixesWrongParticleAndKeepsLowercase() async throws {
        let output = try await Self.engine.proofread(
            "is this correct grammar? i just put one missing test case up to another pr")
        #expect(!output.contains("up to another pr"))
        #expect(output.contains("in another pr"))
        #expect(output.hasPrefix("is this correct grammar?"))
    }

    @Test func fixesVerbPattern() async throws {
        let output = try await Self.engine.proofread("the reviewer suggested me to rename the flag before merging")
        #expect(!output.contains("suggested me to"))
        #expect(output.contains("rename the flag before merging"))
    }

    @Test func leavesTheWritersVoiceAlone() async throws {
        let text = "ngl the demo went way better than i thought, y'all killed it lol"
        let output = try await Self.engine.proofread(text)
        #expect(output == text)
    }
}
