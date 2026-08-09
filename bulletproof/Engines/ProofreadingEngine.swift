import Foundation

nonisolated protocol ProofreadingEngine: Sendable {
    func proofread(_ text: String) async throws -> String
}

nonisolated enum ProofreadingError: LocalizedError {
    case engineUnavailable(reason: String)
    case notImplemented(String)
    case emptyInput
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
        case .timedOut:
            "Proofreading took too long. Try a shorter selection."
        case .inferenceFailed(let underlying):
            underlying.localizedDescription
        }
    }
}
