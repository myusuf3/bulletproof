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
    /// Default guardrails throw guardrailViolation on the user's own words
    /// (profanity, heated messages, legal text); the permissive set exists
    /// exactly for transforming user-provided text.
    static let model = SystemLanguageModel(useCase: .general,
                                           guardrails: .permissiveContentTransformations)

    /// Apple's on-device model has a 4,096-token context window.
    static let contextTokens = 4096

    static var maxInputCharacters: Int {
        ProofreadPrompt.maxInputCharacters(contextTokens: contextTokens)
    }

    func proofread(_ text: String) async throws -> String {
        guard text.count <= Self.maxInputCharacters else {
            throw ProofreadingError.inputTooLong
        }
        switch Self.model.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw ProofreadingError.engineUnavailable(reason: Self.explanation(for: reason))
        }
        // Fresh session per request: proofreading is stateless, and a shared
        // transcript would grow and bleed context between selections.
        let session = LanguageModelSession(model: Self.model,
                                           instructions: ProofreadPrompt.instructions)
        do {
            let response = try await session.respond(
                to: ProofreadPrompt.userPrompt(for: text),
                generating: Correction.self
            )
            return ProofreadPrompt.cleanResponse(response.content.correctedText, original: text)
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapped(error)
        } catch {
            throw ProofreadingError.inferenceFailed(underlying: error)
        }
    }

    /// Every GenerationError becomes user vocabulary - the raw messages talk
    /// about prompts and guardrails, not about the user's selection.
    static func mapped(_ error: LanguageModelSession.GenerationError) -> ProofreadingError {
        switch error {
        case .exceededContextWindowSize:
            .inputTooLong
        case .guardrailViolation, .refusal:
            .guardrailViolation
        case .assetsUnavailable:
            .engineUnavailable(reason: "The Apple Intelligence model isn't available right now. Try again in a few minutes.")
        case .rateLimited:
            .engineUnavailable(reason: "Apple Intelligence is temporarily busy. Try again in a moment.")
        case .concurrentRequests:
            .engineUnavailable(reason: "Another proofread is still running. Try again in a moment.")
        case .unsupportedLanguageOrLocale:
            .engineUnavailable(reason: "Apple Intelligence doesn't support this language. Try a local model instead (Settings > Engine).")
        case .decodingFailure, .unsupportedGuide:
            .inferenceFailed(underlying: error)
        @unknown default:
            .inferenceFailed(underlying: error)
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
