import Foundation
import Testing
@testable import bulletproof

/// Real-inference checks against the installed fine-tune. Runs only on
/// machines that have it downloaded (CI skips - no model there). Fails
/// against snapshots before run7, which either miss the particle fix or
/// reword the sentence around it.
@Suite(.enabled(if: ModelStore().isInstalled(ModelCatalog.recommendedProofreaderID)),
       .serialized)
struct FineTuneIntegrationTests {
    private static let engine = LocalModelEngine(
        modelDirectory: ModelStore().directory(for: ModelCatalog.recommendedProofreaderID))

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
