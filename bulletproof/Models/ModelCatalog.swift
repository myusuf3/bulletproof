import Foundation

nonisolated struct CatalogModel: Identifiable, Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case proofreading, speech
    }

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
    var kind: Kind = .proofreading
    /// Repo files to fetch; nil downloads the whole snapshot. Speech repos
    /// ship training checkpoints ten times the size of the runtime model.
    var files: [String]? = nil
    /// Repo folder holding the MLX build; only its files are fetched, and they
    /// install at the model root. The fine-tune repo keeps bf16 weights (7.6 GB)
    /// at its root and the 4-bit MLX model in `mlx-4bit/`.
    var subfolder: String? = nil

    /// (remote path, path inside the installed model directory, size) for each
    /// file to download, after the `files` and `subfolder` filters.
    func downloadPlan(_ listed: [HFFile]) -> [(remote: String, local: String, size: Int64?)] {
        listed.compactMap { file in
            var local = file.rfilename
            if let subfolder {
                let prefix = subfolder.hasSuffix("/") ? subfolder : subfolder + "/"
                guard local.hasPrefix(prefix) else { return nil }
                local.removeFirst(prefix.count)
            }
            guard files?.contains(local) ?? true, !local.isEmpty else { return nil }
            return (file.rfilename, local, file.size)
        }
    }
}

/// Curated downloads: speech-to-text for dictation, and proofreading
/// backups for Apple Intelligence. Proofreaders are capped at 4B parameters so
/// every 8 GB Apple silicon Mac can run them, and limited to architectures
/// MLX Swift can actually load (qwen3, gemma3) - never list a model users
/// can download but not run. Gemma 4 E4B joins once mlx-swift-lm registers
/// the gemma4 architecture (ml-explore/mlx-swift-lm#282).
nonisolated enum ModelCatalog {
    /// The app's own fine-tune: listed first, and the default engine once installed.
    static let recommendedProofreaderID = "myusuf3/bulletproof-qwen3-4b-finetune"

    static let all: [CatalogModel] = [
        CatalogModel(
            // Qwen3 4B fine-tuned for bulletproof (LoRA merged, MLX 4-bit, group 64;
            // HF tag run8-final). Full app pipeline, 2,171-case eval: 93.4% pass vs
            // 85.9% for run5-final, 0/14 request lookalikes answered. Trained with
            // ProofreadPrompt's current typed instructions. Model card has the
            // details. The default proofreader once installed.
            id: ModelCatalog.recommendedProofreaderID,
            displayName: "Bulletproof Proofreader (Qwen3 4B, fine-tuned)",
            blurb: "Tuned for this app: fixes errors, keeps your style",
            approxDownloadBytes: 2_263_000_000,
            speed: 4,
            accuracy: 5,
            subfolder: "mlx-4bit"
        ),
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
        whistle,
    ]

    /// Cactus Whistle: on-device speech-to-text, one 16.9 MB file run by
    /// the vendored Needle engine (Packages/Needle).
    static let whistle = CatalogModel(
        id: "Cactus-Compute/whistle",
        displayName: "Whistle",
        blurb: "Tiny, fast dictation in 7 languages - fully offline",
        approxDownloadBytes: 16_919_407,
        speed: 5,
        accuracy: 4,
        kind: .speech,
        files: ["whistle.cact"]
    )

    static let whistleModelFile = "whistle.cact"

    static var proofreading: [CatalogModel] { all.filter { $0.kind == .proofreading } }
    static var speech: [CatalogModel] { all.filter { $0.kind == .speech } }

    /// Installed models that can proofread. Orphans count: every model ever
    /// dropped from the catalog was an MLX proofreading model.
    static func proofreadingIDs(installed: [String]) -> [String] {
        let speechIDs = Set(speech.map(\.id))
        return installed.filter { !speechIDs.contains($0) }
    }

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
