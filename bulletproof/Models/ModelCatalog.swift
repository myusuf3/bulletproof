import Foundation

nonisolated struct CatalogModel: Identifiable, Sendable, Hashable {
    /// Hugging Face repo id, e.g. "mlx-community/gemma-2-9b-it-4bit".
    let id: String
    let displayName: String
    let approxDownloadBytes: Int64
}

/// Curated ~8B-class open models as future local backups for Apple
/// Intelligence. MLX-community 4-bit quants so the on-disk snapshot is
/// directly loadable once MLX inference is wired up.
nonisolated enum ModelCatalog {
    static let all: [CatalogModel] = [
        CatalogModel(
            id: "mlx-community/gemma-2-9b-it-4bit",
            displayName: "Gemma 2 9B Instruct (4-bit)",
            approxDownloadBytes: 5_220_000_000
        ),
        CatalogModel(
            id: "mlx-community/Qwen3-8B-4bit",
            displayName: "Qwen3 8B (4-bit)",
            approxDownloadBytes: 4_620_000_000
        ),
        CatalogModel(
            id: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            displayName: "Qwen2.5 7B Instruct (4-bit)",
            approxDownloadBytes: 4_300_000_000
        ),
    ]

    static func displayName(for id: String) -> String {
        all.first { $0.id == id }?.displayName ?? id
    }
}
