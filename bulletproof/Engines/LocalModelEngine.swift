import Foundation

/// Placeholder for on-device inference with a downloaded model. The directory
/// holds a Hugging Face snapshot, the layout MLX's
/// `ModelConfiguration(directory:)` expects when inference gets wired up.
nonisolated struct LocalModelEngine: ProofreadingEngine {
    let modelDirectory: URL

    func proofread(_ text: String) async throws -> String {
        throw ProofreadingError.notImplemented(
            "Local model inference isn't wired up yet. Switch to Apple Intelligence in Settings."
        )
    }
}
