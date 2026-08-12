import Foundation
import MLXLMCommon

/// On-device inference against a downloaded Hugging Face snapshot via MLX.
/// Load-once residency and eviction live in LocalModelRuntime; this stays a
/// per-request value type like the other engines.
nonisolated struct LocalModelEngine: ProofreadingEngine {
    let modelDirectory: URL
    var runtime: ResidencyCache<ModelContainer> = LocalModelRuntime.shared

    func proofread(_ text: String) async throws -> String {
        let container: ModelContainer
        do {
            container = try await runtime.resource(for: modelDirectory)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProofreadingError.engineUnavailable(reason:
                "The local model couldn't be loaded. Re-download it in Settings > Models, or switch to Apple Intelligence.")
        }
        // Fresh session per request: ChatSession isn't thread-safe and
        // proofreading is stateless. No guided generation on MLX - the
        // instructions plus cleanResponse() are the output-shaping mechanism.
        let session = ChatSession(container,
                                  instructions: ProofreadPrompt.instructions,
                                  generateParameters: Self.parameters(for: text))
        do {
            let response = try await session.respond(to: ProofreadPrompt.userPrompt(for: text))
            await runtime.touch()
            return ProofreadPrompt.cleanResponse(response, original: text)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProofreadingError.inferenceFailed(underlying: error)
        }
    }

    /// Corrections are roughly input-sized; 2x plus slack absorbs expansion
    /// without letting a runaway generation eat the 55s budget. ~3 chars per
    /// token is conservative for prose on these tokenizers.
    static func maxTokens(forInputLength characters: Int) -> Int {
        let estimatedInputTokens = max(16, characters / 3)
        return min(4096, estimatedInputTokens * 2 + 128)
    }

    static func parameters(for text: String) -> GenerateParameters {
        var params = GenerateParameters(temperature: 0)
        params.maxTokens = maxTokens(forInputLength: text.count)
        params.maxKVSize = 4096
        return params
    }
}
