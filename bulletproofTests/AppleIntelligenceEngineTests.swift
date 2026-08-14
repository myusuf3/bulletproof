import FoundationModels
import Foundation
import Testing
@testable import bulletproof

struct AppleIntelligenceEngineTests {
    private var context: LanguageModelSession.GenerationError.Context {
        .init(debugDescription: "test")
    }

    /// Collapses associated values so tests can compare cases directly.
    private func caseName(_ error: ProofreadingError) -> String {
        switch error {
        case .engineUnavailable: "engineUnavailable"
        case .notImplemented: "notImplemented"
        case .emptyInput: "emptyInput"
        case .inputTooLong: "inputTooLong"
        case .guardrailViolation: "guardrailViolation"
        case .unusableOutput: "unusableOutput"
        case .timedOut: "timedOut"
        case .inferenceFailed: "inferenceFailed"
        }
    }

    @Test func oversizedInputThrowsBeforeAvailabilityCheck() async {
        // Runs on machines without Apple Intelligence (CI) - the cap must be
        // checked before availability or this throws engineUnavailable there.
        let engine = AppleIntelligenceEngine()
        let text = String(repeating: "a", count: AppleIntelligenceEngine.maxInputCharacters + 1)
        do {
            _ = try await engine.proofread(text)
            Issue.record("expected inputTooLong")
        } catch let error as ProofreadingError {
            #expect(caseName(error) == "inputTooLong")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func inputCapKeepsFullExchangeInsideContextWindow() {
        let cap = AppleIntelligenceEngine.maxInputCharacters
        let inputTokens = cap / 3
        let instructionTokens = ProofreadPrompt.instructions.count / 3
        // A correction is roughly input-sized; 2x + slack mirrors the local
        // engine's generation budget.
        #expect(instructionTokens + inputTokens + (inputTokens * 2 + 128)
                <= AppleIntelligenceEngine.contextTokens)
        // The cap must stay roomy enough for real selections (a few paragraphs).
        #expect(cap > 2000)
    }

    @Test func contextOverflowMapsToInputTooLong() {
        #expect(caseName(AppleIntelligenceEngine.mapped(.exceededContextWindowSize(context))) == "inputTooLong")
    }

    @Test func guardrailAndRefusalMapToGuardrailViolation() {
        #expect(caseName(AppleIntelligenceEngine.mapped(.guardrailViolation(context))) == "guardrailViolation")
        let refusal = LanguageModelSession.GenerationError.Refusal(transcriptEntries: [])
        #expect(caseName(AppleIntelligenceEngine.mapped(.refusal(refusal, context))) == "guardrailViolation")
    }

    @Test func transientAndCapabilityCasesMapToEngineUnavailable() {
        for error: LanguageModelSession.GenerationError in [
            .assetsUnavailable(context),
            .rateLimited(context),
            .concurrentRequests(context),
            .unsupportedLanguageOrLocale(context),
        ] {
            let mapped = AppleIntelligenceEngine.mapped(error)
            #expect(caseName(mapped) == "engineUnavailable")
            // Every reason must be user vocabulary, never an empty fallthrough.
            #expect(mapped.errorDescription?.isEmpty == false)
        }
    }

    @Test func internalFailuresKeepTheUnderlyingError() {
        for error: LanguageModelSession.GenerationError in [
            .decodingFailure(context),
            .unsupportedGuide(context),
        ] {
            #expect(caseName(AppleIntelligenceEngine.mapped(error)) == "inferenceFailed")
        }
    }

    @Test func engineUsesPermissiveGuardrailsModel() {
        // The configured model is held once and reused - proofreading the
        // user's own text must not trip default content guardrails.
        _ = AppleIntelligenceEngine.model
    }
}
