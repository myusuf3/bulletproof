import Foundation

nonisolated struct CatalogModel: Identifiable, Sendable, Hashable {
    /// Hugging Face repo id, e.g. "mlx-community/Qwen3-4B-Instruct-2507-4bit".
    let id: String
    let displayName: String
    /// One-line description shown under the name in the Models tab.
    let blurb: String
    let approxDownloadBytes: Int64
    /// Relative ratings on a 1...5 scale, shown as segment bars in the
    /// Models tab. Judged against the other catalog entries, not absolutes.
    let speed: Int
    let accuracy: Int
}

/// Curated local backups for Apple Intelligence. Capped at 4B parameters so
/// every 8 GB Apple silicon Mac can run them, and limited to architectures
/// MLX Swift can actually load (qwen3, gemma3) - never list a model users
/// can download but not run. Gemma 4 E4B joins once mlx-swift-lm registers
/// the gemma4 architecture (ml-explore/mlx-swift-lm#282).
nonisolated enum ModelCatalog {
    static let all: [CatalogModel] = [
        CatalogModel(
            id: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
            displayName: "Qwen3 4B Instruct (4-bit)",
            blurb: "Top benchmark scores - runs on any Apple silicon Mac",
            approxDownloadBytes: 2_280_000_000,
            speed: 4,
            // Measured, not vibes: 1.000 on the proofreading benchmark
            // across four runs vs Apple Intelligence's 0.84 (BenchResults/).
            accuracy: 4
        ),
        CatalogModel(
            id: "mlx-community/gemma-3-4b-it-4bit",
            displayName: "Gemma 3 4B Instruct (4-bit)",
            blurb: "Strong in 140+ languages - best for non-English text",
            approxDownloadBytes: 3_440_000_000,
            speed: 3,
            accuracy: 4
        ),
    ]

    static func displayName(for id: String) -> String {
        all.first { $0.id == id }?.displayName ?? id
    }

    /// Installed models that are no longer in the catalog - they must stay
    /// visible so users can reclaim the disk space.
    static func orphanIDs(installed: [String]) -> [String] {
        let cataloged = Set(all.map(\.id))
        return installed.filter { !cataloged.contains($0) }.sorted()
    }
}
