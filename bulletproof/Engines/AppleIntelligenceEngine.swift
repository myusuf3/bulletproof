import Foundation
import FoundationModels

/// Constrained decoding keeps the output shaped as a correction; without it
/// the on-device model drifts into answering request-like text.
@Generable
nonisolated struct Correction {
    // The guide is a second instruction channel only this engine sees, so it
    // carries the same keep-the-writer's-style policy as the system prompt.
    @Guide(description: "The input text with every spelling and grammar mistake fixed, including subject-verb agreement, verb tense, articles, missing apostrophes, and misused words (their/there, your/you're, its/it's, then/than). Everything else stays exactly as written: wording, capitalization (lowercase stays lowercase), slang, contractions, emoji, punctuation style, line breaks, and backticked code. Never a reply to the text.")
    var correctedText: String
}

/// The dictation path's output type. Transcripts are lowercase and
/// unpunctuated by accident, so the typed-text guide ("lowercase stays
/// lowercase") would leave them raw.
@Generable
nonisolated struct DictationCorrection {
    @Guide(description: "The transcript written as correct text: sentence punctuation and capital letters added, misheard soundalike words fixed, contractions kept. The speaker's words otherwise unchanged. Never a reply to the text.")
    var correctedText: String
}

nonisolated struct AppleIntelligenceEngine: ProofreadingEngine {
    var instructions = ProofreadPrompt.instructions

    /// Greedy decoding: a proofread has one right answer, and default sampling
    /// made output vary run to run (typed pass 0.68-0.80 across identical runs).
    /// Matches the local engine's temperature 0.
    static let options = GenerationOptions(sampling: .greedy)

    /// The dictation path is identified by its prompt (AppState passes
    /// ProofreadPrompt.dictationInstructions), and gets the matching guide.
    var isDictation: Bool { instructions == ProofreadPrompt.dictationInstructions }

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
                                           instructions: instructions)
        do {
            let prompt = ProofreadPrompt.userPrompt(for: text)
            let corrected = isDictation
                ? try await session.respond(to: prompt, generating: DictationCorrection.self,
                                            options: Self.options).content.correctedText
                : try await session.respond(to: prompt, generating: Correction.self,
                                            options: Self.options).content.correctedText
            return ProofreadPrompt.cleanResponse(corrected, original: text, keepsLowercase: !isDictation,
                                                 sentenceCases: isDictation)
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapped(error)
        } catch {
            throw ProofreadingError.inferenceFailed(underlying: error)
        }
    }

    func prewarm() async {
        guard case .available = Self.model.availability else { return }
        LanguageModelSession(model: Self.model,
                             instructions: instructions).prewarm()
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
