import Foundation
import Testing
@testable import bulletproof

private struct CannedEngine: ProofreadingEngine {
    var output: String
    func proofread(_ text: String) async throws -> String { output }
}

private final class FakeScorer: SpanScorer, @unchecked Sendable {
    var canned: SpanScores
    private(set) var scoredSpans: [EditDiff.Span] = []

    init(replacement: Double?, original: Double? = nil, suffix: Double? = nil) {
        canned = SpanScores(replacement: replacement, original: original,
                            suffixAfterReplacement: suffix)
    }

    func scores(for span: EditDiff.Span) async -> SpanScores {
        scoredSpans.append(span)
        return canned
    }
}

struct ScoredGateEngineTests {
    // Round numbers so these pin gate behavior independent of the tuned
    // production defaults (those are pinned in ScoredVerdictTests).
    private let thresholds = ScoringThresholds(minimumMeanLogProbability: -6.0,
                                               originalVetoMargin: 1.0,
                                               minimumSuffixMeanLogProbability: -7.0)

    @Test func plausibleEditPassesThrough() async throws {
        let scorer = FakeScorer(replacement: -2.0, original: -5.0, suffix: -3.0)
        let engine = ScoredGateEngine(wrapped: CannedEngine(output: "the cat sat"),
                                      scorer: scorer)
        #expect(try await engine.proofread("teh cat sat") == "the cat sat")
        #expect(scorer.scoredSpans.count == 1)
        #expect(scorer.scoredSpans[0].replacement == "the")
    }

    @Test func implausibleEditIsRejected() async {
        let scorer = FakeScorer(replacement: -9.0)
        let engine = ScoredGateEngine(wrapped: CannedEngine(output: "the affect was strong"),
                                      scorer: scorer, thresholds: thresholds)
        do {
            _ = try await engine.proofread("the effect was strong")
            Issue.record("expected unusableOutput")
        } catch let error as ProofreadingError {
            guard case .unusableOutput(.implausibleEdit) = error else {
                Issue.record("expected implausibleEdit, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func originalReadingBetterVetoes() async {
        // The scored version of "the user wrote it that way on purpose".
        let scorer = FakeScorer(replacement: -4.0, original: -2.0, suffix: -3.0)
        let engine = ScoredGateEngine(wrapped: CannedEngine(output: "We hired John yesterday."),
                                      scorer: scorer, thresholds: thresholds)
        await #expect(throws: ProofreadingError.self) {
            _ = try await engine.proofread("We hired Jon yesterday.")
        }
    }

    @Test func unscorableSpanFailsOpen() async throws {
        let scorer = FakeScorer(replacement: nil)
        let engine = ScoredGateEngine(wrapped: CannedEngine(output: "the cat sat"),
                                      scorer: scorer)
        #expect(try await engine.proofread("teh cat sat") == "the cat sat")
    }

    @Test func unchangedOutputNeverTouchesTheScorer() async throws {
        let scorer = FakeScorer(replacement: -99.0)
        let engine = ScoredGateEngine(wrapped: CannedEngine(output: "clean text here"),
                                      scorer: scorer)
        #expect(try await engine.proofread("clean text here") == "clean text here")
        #expect(scorer.scoredSpans.isEmpty)
    }

    @Test func heavyRewritesAreLeftToTheOverlapGate() async throws {
        // Many changed spans = a rewrite; lowOverlap owns that class, and
        // scoring five spans would burn latency for a redundant answer.
        let scorer = FakeScorer(replacement: -99.0)
        let engine = ScoredGateEngine(wrapped: CannedEngine(
            output: "one B two D three F four H five J"), scorer: scorer)
        _ = try await engine.proofread("one A two C three E four G five I")
        #expect(scorer.scoredSpans.isEmpty)
    }

    @Test func pureDeletionsAreNotScored() async throws {
        let scorer = FakeScorer(replacement: -99.0)
        let engine = ScoredGateEngine(wrapped: CannedEngine(output: "I went to the store"),
                                      scorer: scorer)
        #expect(try await engine.proofread("I went to to the store") == "I went to the store")
        #expect(scorer.scoredSpans.isEmpty)
    }
}

/// Real-inference sanity checks for the MLX scorer, gated on the installed
/// model like LocalModelIntegrationTests. Loose assertions on purpose.
@Suite(.enabled(if: ModelStore().isInstalled("mlx-community/Qwen3-4B-Instruct-2507-4bit")),
       .serialized)
struct MLXSpanScorerIntegrationTests {
    private static let scorer = MLXSpanScorer(
        modelDirectory: ModelStore().directory(for: "mlx-community/Qwen3-4B-Instruct-2507-4bit"))

    @Test func naturalWordOutscoresAbsurdWordInContext() async throws {
        let natural = await Self.scorer.scores(for: EditDiff.Span(
            anchor: "the cat sat on the", original: "matt", replacement: "mat", suffix: ""))
        let absurd = await Self.scorer.scores(for: EditDiff.Span(
            anchor: "the cat sat on the", original: "matt", replacement: "spreadsheet", suffix: ""))
        let naturalScore = try #require(natural.replacement)
        let absurdScore = try #require(absurd.replacement)
        #expect(naturalScore > absurdScore)
        #expect(naturalScore < 0)
    }

    @Test func originalSideIsScoredWithTheSameAnchor() async throws {
        let scores = await Self.scorer.scores(for: EditDiff.Span(
            anchor: "please review the", original: "documnet", replacement: "document",
            suffix: "before Friday"))
        // A real typo should score clearly worse than its correction.
        let replacement = try #require(scores.replacement)
        let original = try #require(scores.original)
        #expect(replacement > original)
        #expect(scores.suffixAfterReplacement != nil)
    }
}
