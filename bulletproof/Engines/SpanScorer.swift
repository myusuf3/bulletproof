import Foundation
import MLX
import MLXLMCommon
import MLXNN
import os

nonisolated struct SpanScores: Equatable, Sendable {
    let replacement: Double?
    let original: Double?
    let suffixAfterReplacement: Double?
}

/// Scores how plausibly an edit reads in context, as mean log-probabilities.
/// Nil scores mean "couldn't compute" - callers fail open.
nonisolated protocol SpanScorer: Sendable {
    func scores(for span: EditDiff.Span) async -> SpanScores
}

/// Scores with the resident local model: one forward pass over
/// anchor+replacement+suffix (replacement and suffix log-probs sliced from
/// the same logits), a second over anchor+original+suffix for the
/// counterfactual. Never triggers a model load beyond the residency cache.
nonisolated struct MLXSpanScorer: SpanScorer {
    let modelDirectory: URL

    func scores(for span: EditDiff.Span) async -> SpanScores {
        guard !span.replacement.trimmingCharacters(in: .whitespaces).isEmpty,
              let container = try? await LocalModelRuntime.shared.resource(for: modelDirectory) else {
            return SpanScores(replacement: nil, original: nil, suffixAfterReplacement: nil)
        }
        // ChatSession deliberately runs outside the container lock, so two
        // graph submissions can overlap; serialize scoring app-wide.
        return await ScoringSerializer.shared.run { [span] in
            await container.perform { context in
                let (replacement, suffix) = Self.score(anchor: span.anchor, middle: span.replacement,
                                                       suffix: span.suffix, context: context)
                let original: Double?
                if span.original.trimmingCharacters(in: .whitespaces).isEmpty {
                    original = nil
                } else {
                    (original, _) = Self.score(anchor: span.anchor, middle: span.original,
                                               suffix: span.suffix, context: context)
                }
                return SpanScores(replacement: replacement, original: original,
                                  suffixAfterReplacement: suffix)
            }
        }
    }

    /// Mean log-prob of `middle`'s tokens (and of `suffix`'s, from the same
    /// pass) conditioned on what precedes them. Position i's logits predict
    /// token i+1, so rows [start-1, end-1) score tokens [start, end).
    private static func score(anchor: String, middle: String, suffix: String,
                              context: ModelContext) -> (Double?, Double?) {
        let tokenizer = context.tokenizer
        let anchorTokens = anchor.isEmpty ? [] : tokenizer.encode(text: anchor, addSpecialTokens: true)
        let withMiddle = tokenizer.encode(text: joined(anchor, middle), addSpecialTokens: true)
        let fullTokens = suffix.isEmpty
            ? withMiddle
            : tokenizer.encode(text: joined(joined(anchor, middle), suffix), addSpecialTokens: true)

        // BPE can merge across boundaries, in which case these slices would
        // score the wrong tokens - fail open instead.
        guard Array(withMiddle.prefix(anchorTokens.count)) == anchorTokens,
              Array(fullTokens.prefix(withMiddle.count)) == withMiddle else {
            return (nil, nil)
        }
        // With no BOS token an anchorless span's first token has no
        // conditioning position; score from its second token.
        let middleStart = max(anchorTokens.count, 1)
        let middleEnd = withMiddle.count
        guard middleEnd > middleStart else { return (nil, nil) }

        let tokens = MLXArray(fullTokens).expandedDimensions(axis: 0)
        let logits = context.model(tokens, cache: context.model.newCache(parameters: nil))
            .asType(.float32)

        let middleScore = meanLogProb(logits: logits, tokens: fullTokens,
                                      start: middleStart, end: middleEnd)
        let suffixScore = fullTokens.count > middleEnd
            ? meanLogProb(logits: logits, tokens: fullTokens, start: middleEnd, end: fullTokens.count)
            : nil
        return (middleScore, suffixScore)
    }

    private static func meanLogProb(logits: MLXArray, tokens: [Int], start: Int, end: Int) -> Double {
        let rows = logits[0..., (start - 1) ..< (end - 1), 0...]
        let targets = MLXArray(Array(tokens[start ..< end])).expandedDimensions(axis: 0)
        // crossEntropy is logSumExp(logits) - takeAlong(logits, targets):
        // the negative target log-prob.
        let nll = crossEntropy(logits: rows, targets: targets, reduction: .mean)
        return -Double(nll.item(Float.self))
    }

    private static func joined(_ a: String, _ b: String) -> String {
        a.isEmpty ? b : b.isEmpty ? a : a + " " + b
    }
}

/// FIFO, non-reentrant serialization for scoring passes (a plain actor is
/// reentrant across await, which would let passes interleave).
actor ScoringSerializer {
    static let shared = ScoringSerializer()
    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ body: @escaping @Sendable () async -> T) async -> T {
        let previous = tail
        let task = Task { () -> T in
            await previous?.value
            return await body()
        }
        tail = Task { _ = await task.value }
        return await task.value
    }
}

/// Veto layer over an already-gated engine: judges each changed span with
/// the local model and rejects edits that read as implausible. Fails open on
/// every scoring failure - it can only veto, never promote.
nonisolated struct ScoredGateEngine: ProofreadingEngine {
    let wrapped: any ProofreadingEngine
    let scorer: any SpanScorer
    var thresholds = ScoringThresholds()

    private static let logger = Logger(subsystem: "com.mahdiyusuf.bulletproof", category: "scored-gate")
    /// Above this many changed spans the output is a rewrite - lowOverlap's
    /// territory - and scoring would burn latency on a redundant answer.
    private static let maxSpansToScore = 4

    func proofread(_ text: String) async throws -> String {
        let output = try await wrapped.proofread(text)
        let spans = EditDiff.spans(original: text, corrected: output)
        guard !spans.isEmpty, spans.count <= Self.maxSpansToScore else { return output }
        for span in spans where !span.replacement.trimmingCharacters(in: .whitespaces).isEmpty {
            let scores = await scorer.scores(for: span)
            guard let replacement = scores.replacement else { continue }
            if case .rejected(let reason) = ScoredVerdict.evaluate(
                    replacementScore: replacement, originalScore: scores.original,
                    suffixScore: scores.suffixAfterReplacement, thresholds: thresholds) {
                let originalLabel = scores.original.map { String($0) } ?? "-"
                Self.logger.warning("rejected edit: \(reason, privacy: .public) replacement=\(replacement, privacy: .public) original=\(originalLabel, privacy: .public)")
                throw ProofreadingError.unusableOutput(.implausibleEdit)
            }
        }
        return output
    }

    func prewarm() async {
        await wrapped.prewarm()
    }
}
