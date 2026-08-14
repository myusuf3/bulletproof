import Foundation

nonisolated protocol ProofreadingEngine: Sendable {
    func proofread(_ text: String) async throws -> String
    /// Warm-up fired while the copy round-trip burns wall-clock. Failures
    /// stay silent here and surface on the real request.
    func prewarm() async
}

extension ProofreadingEngine {
    func prewarm() async {}
}

nonisolated enum ProofreadingError: LocalizedError {
    case engineUnavailable(reason: String)
    case notImplemented(String)
    case emptyInput
    case inputTooLong
    case guardrailViolation
    case unusableOutput(OutputGate.Rejection)
    case timedOut
    case inferenceFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .engineUnavailable(let reason):
            reason
        case .notImplemented(let message):
            message
        case .emptyInput:
            "No text was selected."
        case .inputTooLong:
            "The selection is too long to proofread. Try a shorter selection."
        case .guardrailViolation:
            "Apple Intelligence declined to proofread this text. Try a local model instead (Settings > Engine)."
        case .unusableOutput(let reason):
            switch reason {
            case .emptyOutput:
                "The model returned nothing, so your text was left unchanged."
            case .replacementCharacter, .introducedControlCharacters:
                "The model returned garbled text, so your selection was left unchanged."
            case .overExpansion, .lowOverlap:
                "The model rewrote instead of correcting, so your selection was left unchanged."
            case .introducedMisspelling:
                "The model's correction introduced a misspelling, so your selection was left unchanged."
            }
        case .timedOut:
            "Proofreading took too long. Try a shorter selection."
        case .inferenceFailed(let underlying):
            underlying.localizedDescription
        }
    }
}
