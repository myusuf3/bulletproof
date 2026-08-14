import Foundation

nonisolated protocol ProofreadingEngine: Sendable {
    func proofread(_ text: String) async throws -> String
}

nonisolated enum ProofreadingError: LocalizedError {
    case engineUnavailable(reason: String)
    case notImplemented(String)
    case emptyInput
    case inputTooLong
    case guardrailViolation
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
        case .timedOut:
            "Proofreading took too long. Try a shorter selection."
        case .inferenceFailed(let underlying):
            underlying.localizedDescription
        }
    }
}
