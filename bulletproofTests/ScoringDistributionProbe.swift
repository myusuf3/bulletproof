import Foundation
import Testing
@testable import bulletproof

/// Tuning instrument, not a pass/fail test: prints the score triples for
/// known-good edits (the corpus fix cases) and known-bad edits (the
/// corruption classes the benchmark caught Apple Intelligence producing),
/// so thresholds are chosen from measured distributions. Run with
/// TEST_RUNNER_BULLETPROOF_BENCH=1; read lines prefixed PROBE.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BULLETPROOF_BENCH"] == "1"
                    && ModelStore().isInstalled("mlx-community/Qwen3-4B-Instruct-2507-4bit")),
       .serialized)
struct ScoringDistributionProbe {
    private static let scorer = MLXSpanScorer(
        modelDirectory: ModelStore().directory(for: "mlx-community/Qwen3-4B-Instruct-2507-4bit"))

    private static let badEdits: [(String, String, String)] = [
        ("jon-john", "We hired Jon yesterday.", "We hired John yesterday."),
        ("profanity-censored", "This fucking build has been broken all day.",
         "This broken build has been broken all day."),
        ("dialect-erased", "Y'all ain't gonna believe what happened at the demo.",
         "You'll never believe what happened at the demo."),
        ("homophone-wrong-way", "the effect of caffeine on sleep", "the affect of caffeine on sleep"),
        ("brand-capitalized", "The app is called bulletproof, all lowercase.",
         "The app is called Bulletproof, all lowercase."),
        ("priya-maya", "ok I'll send the deck to Priya", "ok I'll send the deck to Maya"),
    ]

    @Test func printScoreDistributions() async throws {
        let cases = try BenchCorpus.load(from: benchCorpusURL())
        for benchCase in cases {
            guard case .fix(let acceptable) = benchCase.expected, let output = acceptable.first else {
                continue
            }
            await probe(label: "GOOD \(benchCase.id)", input: benchCase.input, output: output)
        }
        for (id, input, output) in Self.badEdits {
            await probe(label: "BAD \(id)", input: input, output: output)
        }
    }

    private func probe(label: String, input: String, output: String) async {
        for span in EditDiff.spans(original: input, corrected: output)
        where !span.replacement.trimmingCharacters(in: .whitespaces).isEmpty {
            let scores = await Self.scorer.scores(for: span)
            let repl = scores.replacement.map { String(format: "%.2f", $0) } ?? "nil"
            let orig = scores.original.map { String(format: "%.2f", $0) } ?? "nil"
            let suff = scores.suffixAfterReplacement.map { String(format: "%.2f", $0) } ?? "nil"
            print("PROBE \(label) '\(span.original)'->'\(span.replacement)' repl=\(repl) orig=\(orig) suffix=\(suff)")
        }
    }
}
