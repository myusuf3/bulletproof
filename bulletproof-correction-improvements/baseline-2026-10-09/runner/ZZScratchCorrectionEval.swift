// Eval runner used for this run. Lives outside the test target on purpose;
// copy into bulletproofTests/ to re-run (see ../README.md), then remove.
import Foundation
import FoundationModels
import Testing
@testable import bulletproof

private struct FixedOutputEngine: ProofreadingEngine {
    let output: String
    func proofread(_ text: String) async throws -> String { output }
}

private struct EvalRow: Encodable {
    let id: String
    let engine: String
    let input: String
    let raw: String?
    let rawError: String?
    let ms: Double
    let gated: String
    let scored: String
    let spans: [SpanRow]
}

/// One changed span as the verify gate sees it - the raw material for
/// threshold tuning.
private struct SpanRow: Encodable {
    let original: String
    let replacement: String
    let replacementScore: Double?
    let originalScore: Double?
    let suffixScore: Double?
    let replacementTotal: Double?
    let originalTotal: Double?
    let replacementTokenCount: Int?
    let originalTokenCount: Int?
    let verdict: String
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["BULLETPROOF_EVAL_CORPUS"] != nil),
       .serialized)
struct ZZScratchCorrectionEval {
    private struct Case: Decodable { let id: String; let input: String }

    /// Gate outcome as the user would see it: the pasted text, or REJECTED(reason).
    private static func outcome(_ engine: any ProofreadingEngine, _ input: String) async -> String {
        do {
            return try await engine.proofread(input)
        } catch {
            return "REJECTED(\(ProofreadOutcome.from(error).label))"
        }
    }

    /// Mirrors ScoredGateEngine: only outputs with 1...4 changed spans are
    /// scored (its maxSpansToScore is private), whitespace-only replacements
    /// are skipped, and cosmetic / typo-fix spans are accepted unscored
    /// ("triaged").
    private static func spanRows(input: String, output: String, scorer: any SpanScorer) async -> [SpanRow] {
        let spans = EditDiff.spans(original: input, corrected: output)
        guard (1...4).contains(spans.count) else { return [] }
        let gate = ScoredGateEngine(wrapped: FixedOutputEngine(output: output), scorer: scorer)
        var rows: [SpanRow] = []
        for span in spans where !span.replacement.trimmingCharacters(in: .whitespaces).isEmpty {
            if await gate.isAcceptedWithoutScoring(span) {
                rows.append(SpanRow(original: span.original, replacement: span.replacement,
                                    replacementScore: nil, originalScore: nil, suffixScore: nil,
                                    replacementTotal: nil, originalTotal: nil,
                                    replacementTokenCount: nil, originalTokenCount: nil, verdict: "triaged"))
                continue
            }
            let scores = await scorer.scores(for: span)
            let verdict: String
            if scores.replacement != nil {
                verdict = switch ScoredVerdict.evaluate(scores, thresholds: ScoringThresholds()) {
                case .accepted: "accepted"
                case .rejected(let reason): reason
                }
            } else {
                verdict = "unscored"
            }
            rows.append(SpanRow(original: span.original, replacement: span.replacement,
                                replacementScore: scores.replacement, originalScore: scores.original,
                                suffixScore: scores.suffixAfterReplacement,
                                replacementTotal: scores.replacementTotal, originalTotal: scores.originalTotal,
                                replacementTokenCount: scores.replacementTokenCount,
                                originalTokenCount: scores.originalTokenCount, verdict: verdict))
        }
        return rows
    }

    @Test func run() async throws {
        let env = ProcessInfo.processInfo.environment
        let corpus = URL(fileURLWithPath: env["BULLETPROOF_EVAL_CORPUS"]!)
        let out = URL(fileURLWithPath: env["BULLETPROOF_EVAL_OUT"]!)
        let cases = try String(contentsOf: corpus, encoding: .utf8)
            .split(separator: "\n")
            .map { try JSONDecoder().decode(Case.self, from: Data($0.utf8)) }

        // Real vocabulary words, scratch storage, frozen: the run must not
        // teach the user's vocabulary anything, and learning mid-run would make
        // results depend on case and engine order (the 2026-10-09 baseline
        // learned the typo "signficantly" this way and vetoed s5-061).
        let scratchDefaults = UserDefaults(suiteName: "bulletproof-eval-scratch")!
        scratchDefaults.removePersistentDomain(forName: "bulletproof-eval-scratch")
        scratchDefaults.set(UserDefaults.standard.stringArray(forKey: "personalVocabularyWords") ?? [],
                            forKey: "personalVocabularyWords")
        let vocabulary = await MainActor.run {
            PersonalVocabulary(defaults: scratchDefaults, isUnknownWord: { _ in false })
        }

        // The local model both generates and scores, as in the app when a
        // local engine is selected.
        let store = ModelStore()
        let qwenID = "mlx-community/Qwen3-4B-Instruct-2507-4bit"
        let localID = env["BULLETPROOF_EVAL_LOCAL_MODEL"] ?? qwenID
        try #require(store.isInstalled(localID), "\(localID) is not installed")
        let scorer = MLXSpanScorer(modelDirectory: store.directory(for: localID))
        // (typed-text engine, dictation-path engine): s3 is the dictation
        // slice and goes through ProofreadPrompt.dictationInstructions, as
        // DictationController does in the app.
        var engines: [(String, any ProofreadingEngine, any ProofreadingEngine)] = []
        if env["BULLETPROOF_EVAL_SKIP_AI"] != "1", case .available = AppleIntelligenceEngine.model.availability {
            engines.append(("appleIntelligence", AppleIntelligenceEngine(),
                            AppleIntelligenceEngine(instructions: ProofreadPrompt.dictationInstructions)))
        }
        let localDirectory = store.directory(for: localID)
        engines.append((localID == qwenID ? "qwen3-4b" : "local(\(localID))",
                        LocalModelEngine(modelDirectory: localDirectory),
                        LocalModelEngine(modelDirectory: localDirectory,
                                         instructions: ProofreadPrompt.dictationInstructions)))

        FileManager.default.createFile(atPath: out.path, contents: nil)
        let handle = try FileHandle(forWritingTo: out)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        for (name, typedEngine, dictationEngine) in engines {
            await typedEngine.prewarm()
            for c in cases {
                let engine = c.id.hasPrefix("s3-") ? dictationEngine : typedEngine
                let start = ContinuousClock.now
                var raw: String?
                var rawError: String?
                do {
                    raw = try await withTimeout(seconds: 55) { try await engine.proofread(c.input) }
                } catch {
                    rawError = ProofreadOutcome.from(error).label
                }
                let ms = (ContinuousClock.now - start) / .milliseconds(1)
                var gated = "ENGINE_FAILED"
                var scored = "ENGINE_FAILED"
                var spans: [SpanRow] = []
                if let raw {
                    spans = await Self.spanRows(input: c.input, output: raw, scorer: scorer)
                    let gate = OutputGatedEngine(wrapped: FixedOutputEngine(output: raw), vocabulary: vocabulary)
                    gated = await Self.outcome(gate, c.input)
                    // ScoredGateEngine's verdict, derived from the spans already
                    // scored instead of scoring every span a second time. Matched
                    // the real ScoredGateEngine on 400/400 rows of the 2026-10-09
                    // Qwen re-run; re-check if ScoredGateEngine's logic changes.
                    let vetoed = spans.contains { !["accepted", "unscored", "triaged"].contains($0.verdict) }
                    scored = gated.hasPrefix("REJECTED(") ? gated
                        : vetoed ? "REJECTED(\(ProofreadOutcome.from(ProofreadingError.unusableOutput(.implausibleEdit)).label))"
                        : raw
                }
                let row = EvalRow(id: c.id, engine: name, input: c.input, raw: raw, rawError: rawError,
                                  ms: ms, gated: gated, scored: scored, spans: spans)
                handle.write(try encoder.encode(row) + Data("\n".utf8))
            }
        }
        try handle.close()
    }
}
