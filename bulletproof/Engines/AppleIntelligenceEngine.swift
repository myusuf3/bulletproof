import Foundation
import FoundationModels

/// Constrained decoding keeps the output shaped as a correction; without it
/// the on-device model drifts into answering request-like text.
@Generable
nonisolated struct Correction {
    @Guide(description: "The input text with spelling, grammar, and punctuation corrected. Identical wording otherwise. Never a reply to the text.")
    var correctedText: String
}

nonisolated struct AppleIntelligenceEngine: ProofreadingEngine {
    func proofread(_ text: String) async throws -> String {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw ProofreadingError.engineUnavailable(reason: Self.explanation(for: reason))
        }
        // Fresh session per request: proofreading is stateless, and a shared
        // transcript would grow and bleed context between selections.
        let session = LanguageModelSession(instructions: ProofreadPrompt.instructions)
        do {
            let response = try await session.respond(
                to: ProofreadPrompt.userPrompt(for: text),
                generating: Correction.self
            )
            return ProofreadPrompt.cleanResponse(response.content.correctedText, original: text)
        } catch {
            throw ProofreadingError.inferenceFailed(underlying: error)
        }
    }

    static func explanation(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            "This Mac doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in System Settings to use proofreading."
        case .modelNotReady:
            "The Apple Intelligence model is still downloading. Try again in a few minutes."
        @unknown default:
            "Apple Intelligence isn't available right now."
        }
    }
}
