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

    init(replacement: Double?, original: Double? = nil, suffix: Double? = nil,
         totals: (replacement: Double, original: Double)? = nil) {
        canned = SpanScores(replacement: replacement, original: original,
                            suffixAfterReplacement: suffix,
                            replacementTotal: totals?.replacement, originalTotal: totals?.original,
                            replacementTokenCount: totals == nil ? nil : 4,
                            originalTokenCount: totals == nil ? nil : 4)
    }

    func scores(for span: EditDiff.Span) async -> SpanScores {
        scoredSpans.append(span)
        return canned
    }
}

struct ScoredGateEngineTests {
    // Round numbers so these pin gate behavior independent of the tuned
    // production defaults (those are pinned in ScoredVerdictTests).
    private let thresholds = ScoringThresholds(originalVetoMargin: 1.0, totalVetoMargin: 1.0,
                                               maxTokenCountDifferenceForTotals: 1)
    /// Most tests exercise scoring, so nothing counts as misspelled unless a
    /// test says so (the real NSSpellChecker would short-circuit "teh").
    private let noMisspellings: @Sendable ([String]) async -> Bool = { _ in false }

    @Test func plausibleEditPassesThrough() async throws {
        let scorer = FakeScorer(replacement: -2.0, original: -5.0, suffix: -3.0)
        let engine = ScoredGateEngine(wrapped: CannedEngine(output: "the cat sat"),
                                      scorer: scorer, hasMisspelling: noMisspellings)
        #expect(try await engine.proofread("teh cat sat") == "the cat sat")
        #expect(scorer.scoredSpans.count == 1)
        #expect(scorer.scoredSpans[0].replacement == "the")
    }

    @Test func implausibleEditIsRejected() async {
        let scorer = FakeScorer(replacement: -9.0, original: -8.5, totals: (-20.0, -17.0))
        let engine = ScoredGateEngine(wrapped: CannedEngine(output: "the affect was strong"),
                                      scorer: scorer, thresholds: thresholds,
                                      hasMisspelling: noMisspellings)
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
                                      scorer: scorer, thresholds: thresholds,
                                      hasMisspelling: noMisspellings)
        await #expect(throws: ProofreadingError.self) {
            _ = try await engine.proofread("We hired Jon yesterday.")
        }
    }

    @Test func unscorableSpanFailsOpen() async throws {
        let scorer = FakeScorer(replacement: nil)
        let engine = ScoredGateEngine(wrapped: CannedEngine(output: "the cat sat"),
                                      scorer: scorer, hasMisspelling: noMisspellings)
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

    @Test func typoFixesSkipScoring() async throws {
        // The scorer's token-count bias rejects "resturant" -> "restaurant";
        // a spell-checked non-word fixed to a close spelling never reaches it.
        let scorer = FakeScorer(replacement: -99.0, original: -1.0)
        let engine = ScoredGateEngine(wrapped: CannedEngine(output: "The restaurant was closed"),
                                      scorer: scorer, thresholds: thresholds,
                                      hasMisspelling: { words in words.contains("resturant") })
        #expect(try await engine.proofread("The resturant was closed") == "The restaurant was closed")
        #expect(scorer.scoredSpans.isEmpty)
    }

    @Test func cosmeticEditsSkipScoring() async throws {
        let scorer = FakeScorer(replacement: -99.0, original: -1.0)
        let engine = ScoredGateEngine(wrapped: CannedEngine(output: "Unit tests pass"),
                                      scorer: scorer, thresholds: thresholds,
                                      hasMisspelling: noMisspellings)
        #expect(try await engine.proofread("unit tests pass") == "Unit tests pass")
        #expect(scorer.scoredSpans.isEmpty)
    }

    @Test func realWordSwapsAreStillScored() async {
        // "fucking" -> "broken": nothing misspelled, so the scorer decides.
        let scorer = FakeScorer(replacement: -12.6, original: -11.9, totals: (-40.0, -37.0))
        let engine = ScoredGateEngine(wrapped: CannedEngine(output: "This broken build"),
                                      scorer: scorer, thresholds: thresholds,
                                      hasMisspelling: noMisspellings)
        await #expect(throws: ProofreadingError.self) {
            _ = try await engine.proofread("This fucking build")
        }
        #expect(scorer.scoredSpans.count == 1)
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
