import Foundation
import MLX
import MLXLMCommon
import MLXNN
import os

nonisolated struct SpanScores: Equatable, Sendable {
    /// Mean log-prob per token of each side of the span, given the anchor.
    let replacement: Double?
    let original: Double?
    let suffixAfterReplacement: Double?
    /// Summed log-prob of span + rest of the text, for each side, and how many
    /// tokens each sum covers (totals only compare at matched lengths).
    var replacementTotal: Double? = nil
    var originalTotal: Double? = nil
    var replacementTokenCount: Int? = nil
    var originalTokenCount: Int? = nil

    init(replacement: Double?, original: Double?, suffixAfterReplacement: Double?,
         replacementTotal: Double? = nil, originalTotal: Double? = nil,
         replacementTokenCount: Int? = nil, originalTokenCount: Int? = nil) {
        self.replacement = replacement
        self.original = original
        self.suffixAfterReplacement = suffixAfterReplacement
        self.replacementTotal = replacementTotal
        self.originalTotal = originalTotal
        self.replacementTokenCount = replacementTokenCount
        self.originalTokenCount = originalTokenCount
    }
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
                let replacement = Self.score(anchor: span.anchor, middle: span.replacement,
                                             suffix: span.suffix, context: context)
                let original = span.original.trimmingCharacters(in: .whitespaces).isEmpty
                    ? nil
                    : Self.score(anchor: span.anchor, middle: span.original,
                                 suffix: span.suffix, context: context)
                return SpanScores(replacement: replacement?.middleMean, original: original?.middleMean,
                                  suffixAfterReplacement: replacement?.suffixMean,
                                  replacementTotal: replacement?.total, originalTotal: original?.total,
                                  replacementTokenCount: replacement?.tokenCount,
                                  originalTokenCount: original?.tokenCount)
            }
        }
    }

    private struct PassScores {
        let middleMean: Double
        let suffixMean: Double?
        /// Summed log-prob of middle + suffix tokens, and how many there are.
        let total: Double
        let tokenCount: Int
    }

    /// Log-probs of `middle`'s tokens (and of `suffix`'s, from the same pass)
    /// conditioned on what precedes them. Position i's logits predict token
    /// i+1, so rows [start-1, end-1) score tokens [start, end).
    private static func score(anchor: String, middle: String, suffix: String,
                              context: ModelContext) -> PassScores? {
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
            return nil
        }
        // With no BOS token an anchorless span's first token has no
        // conditioning position; score from its second token.
        let middleStart = max(anchorTokens.count, 1)
        let middleEnd = withMiddle.count
        guard middleEnd > middleStart else { return nil }

        let tokens = MLXArray(fullTokens).expandedDimensions(axis: 0)
        let logits = context.model(tokens, cache: context.model.newCache(parameters: nil))
            .asType(.float32)

        let middleSum = sumLogProb(logits: logits, tokens: fullTokens, start: middleStart, end: middleEnd)
        let suffixCount = fullTokens.count - middleEnd
        let suffixSum = suffixCount > 0
            ? sumLogProb(logits: logits, tokens: fullTokens, start: middleEnd, end: fullTokens.count)
            : nil
        let middleCount = middleEnd - middleStart
        return PassScores(middleMean: middleSum / Double(middleCount),
                          suffixMean: suffixSum.map { $0 / Double(suffixCount) },
                          total: middleSum + (suffixSum ?? 0),
                          tokenCount: middleCount + suffixCount)
    }

    private static func sumLogProb(logits: MLXArray, tokens: [Int], start: Int, end: Int) -> Double {
        let rows = logits[0..., (start - 1) ..< (end - 1), 0...]
        let targets = MLXArray(Array(tokens[start ..< end])).expandedDimensions(axis: 0)
        // crossEntropy is logSumExp(logits) - takeAlong(logits, targets):
        // the negative target log-prob.
        let nll = crossEntropy(logits: rows, targets: targets, reduction: .sum)
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
    /// Whether any of these words is a non-word. A test seam over
    /// SpellCheckGate (NSSpellChecker is main-actor only).
    var hasMisspelling: @Sendable ([String]) async -> Bool = { words in
        await SpellCheckGate.firstMisspelled(in: words) != nil
    }

    private static let logger = Logger(subsystem: "com.mahdiyusuf.bulletproof", category: "scored-gate")
    /// Above this many changed spans the output is a rewrite - lowOverlap's
    /// territory - and scoring would burn latency on a redundant answer.
    private static let maxSpansToScore = 4

    func proofread(_ text: String) async throws -> String {
        let output = try await wrapped.proofread(text)
        let spans = EditDiff.spans(original: text, corrected: output)
        guard !spans.isEmpty, spans.count <= Self.maxSpansToScore else { return output }
        for span in spans where !span.replacement.trimmingCharacters(in: .whitespaces).isEmpty {
            if await isAcceptedWithoutScoring(span) { continue }
            let scores = await scorer.scores(for: span)
            if case .rejected(let reason) = ScoredVerdict.evaluate(scores, thresholds: thresholds) {
                let replacementLabel = scores.replacement.map { String($0) } ?? "-"
                let originalLabel = scores.original.map { String($0) } ?? "-"
                Self.logger.warning("rejected edit: \(reason, privacy: .public) replacement=\(replacementLabel, privacy: .public) original=\(originalLabel, privacy: .public)")
                throw ProofreadingError.unusableOutput(.implausibleEdit)
            }
        }
        return output
    }

    /// Cosmetic edits and non-word typo fixes are where the scorer's token-count
    /// bias vetoes good corrections, and neither can be an absurd swap.
    func isAcceptedWithoutScoring(_ span: EditDiff.Span) async -> Bool {
        if SpanTriage.isCosmetic(span) { return true }
        let originalWords = OutputGate.wordTokens(in: span.original)
        guard await hasMisspelling(originalWords) else { return false }
        return SpanTriage.isTypoFix(span, originalHasMisspelling: true,
                                    replacementHasMisspelling: await hasMisspelling(
                                        OutputGate.wordTokens(in: span.replacement)))
    }

    func prewarm() async {
        await wrapped.prewarm()
    }
}
