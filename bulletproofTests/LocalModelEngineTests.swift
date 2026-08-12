import Foundation
import MLXLMCommon
import Testing
@testable import bulletproof

struct LocalModelEngineTests {
    @Test func maxTokensHasFloorForTinyInput() {
        #expect(LocalModelEngine.maxTokens(forInputLength: 1) == 16 * 2 + 128)
    }

    @Test func maxTokensScalesWithInput() {
        // 3000 chars ~= 1000 tokens -> 2x + 128 slack.
        #expect(LocalModelEngine.maxTokens(forInputLength: 3000) == 2128)
    }

    @Test func maxTokensClampsAtCeiling() {
        #expect(LocalModelEngine.maxTokens(forInputLength: 100_000) == 4096)
    }

    @Test func parametersAreDeterministic() {
        let params = LocalModelEngine.parameters(for: "teh cat")
        #expect(params.temperature == 0)
    }

    @Test func missingModelDirectoryThrowsEngineUnavailable() async {
        let engine = LocalModelEngine(modelDirectory: URL(
            fileURLWithPath: "/nonexistent/\(UUID().uuidString)"))
        do {
            _ = try await engine.proofread("teh cat")
            Issue.record("expected engineUnavailable")
        } catch let error as ProofreadingError {
            guard case .engineUnavailable = error else {
                Issue.record("expected engineUnavailable, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
