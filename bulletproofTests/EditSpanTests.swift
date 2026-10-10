import Testing
@testable import bulletproof

struct EditDiffTests {
    @Test func identicalTextsHaveNoSpans() {
        #expect(EditDiff.spans(original: "the cat sat", corrected: "the cat sat").isEmpty)
    }

    @Test func singleWordSubstitutionCarriesAnchorAndSuffix() {
        let spans = EditDiff.spans(original: "please review teh document today",
                                   corrected: "please review the document today")
        #expect(spans == [EditDiff.Span(anchor: "please review",
                                        original: "teh",
                                        replacement: "the",
                                        suffix: "document today")])
    }

    @Test func changeAtTheStartHasEmptyAnchor() {
        let spans = EditDiff.spans(original: "teh cat sat", corrected: "The cat sat")
        #expect(spans.count == 1)
        #expect(spans[0].anchor == "")
        #expect(spans[0].original == "teh")
        #expect(spans[0].replacement == "The")
        #expect(spans[0].suffix == "cat sat")
    }

    @Test func changeAtTheEndHasEmptySuffix() {
        let spans = EditDiff.spans(original: "wait until tomorow", corrected: "wait until tomorrow")
        #expect(spans.count == 1)
        #expect(spans[0].suffix == "")
    }

    @Test func multipleSeparatedChangesYieldMultipleSpans() {
        let spans = EditDiff.spans(original: "teh cat sat on teh mat",
                                   corrected: "the cat sat on the mat")
        #expect(spans.count == 2)
        #expect(spans[0].original == "teh")
        // Anchor and suffix are the *corrected* side: the text whose
        // coherence the scorer judges.
        #expect(spans[0].suffix == "cat sat on the mat")
        #expect(spans[1].anchor == "the cat sat on")
        #expect(spans[1].original == "teh")
    }

    @Test func insertionHasEmptyOriginalSide() {
        let spans = EditDiff.spans(original: "I went the store", corrected: "I went to the store")
        #expect(spans == [EditDiff.Span(anchor: "I went",
                                        original: "",
                                        replacement: "to",
                                        suffix: "the store")])
    }

    @Test func deletionHasEmptyReplacementSide() {
        let spans = EditDiff.spans(original: "I went to to the store", corrected: "I went to the store")
        #expect(spans.count == 1)
        #expect(spans[0].original == "to")
        #expect(spans[0].replacement == "")
    }

    @Test func adjacentChangedWordsMergeIntoOneSpan() {
        let spans = EditDiff.spans(original: "their welcom here", corrected: "they're welcome here")
        #expect(spans == [EditDiff.Span(anchor: "",
                                        original: "their welcom",
                                        replacement: "they're welcome",
                                        suffix: "here")])
    }

    @Test func punctuationOnlyChangeIsASpan() {
        let spans = EditDiff.spans(original: "whats the plan", corrected: "what's the plan?")
        #expect(spans.count == 2)
        #expect(spans[0].original == "whats")
        #expect(spans[0].replacement == "what's")
        #expect(spans[1].original == "plan")
        #expect(spans[1].replacement == "plan?")
    }
}

struct ScoredVerdictTests {
    // Round numbers: these tests pin the decision logic; the production
    // defaults are pinned separately below.
    private let thresholds = ScoringThresholds(originalVetoMargin: 1.0, totalVetoMargin: 1.0,
                                               maxTokenCountDifferenceForTotals: 1)

    private func scores(_ replacement: Double?, _ original: Double?,
                        totals: (Double, Double)? = nil, counts: (Int, Int) = (3, 3)) -> SpanScores {
        SpanScores(replacement: replacement, original: original, suffixAfterReplacement: -3.0,
                   replacementTotal: totals?.0, originalTotal: totals?.1,
                   replacementTokenCount: totals == nil ? nil : counts.0,
                   originalTokenCount: totals == nil ? nil : counts.1)
    }

    @Test func plausibleEditIsAccepted() {
        #expect(ScoredVerdict.evaluate(scores(-2.0, -5.0, totals: (-10, -14)), thresholds: thresholds) == .accepted)
    }

    @Test func lowReplacementScoreAloneNoLongerVetoes() {
        // The old -12 floor: real-word fixes (past -> passed) and rare
        // correct words (technician) live down there too.
        #expect(ScoredVerdict.evaluate(scores(-14.0, -13.5), thresholds: thresholds) == .accepted)
    }

    @Test func originalReadingMuchBetterVetoesTheEdit() {
        // The "user wrote Priya on purpose" check: original clearly outscores
        // the replacement.
        #expect(ScoredVerdict.evaluate(scores(-4.0, -2.5), thresholds: thresholds)
                == .rejected("originalMoreLikely"))
    }

    @Test func originalSlightlyBetterIsWithinTheMargin() {
        // Ties and small wins for the original are expected - vetoing them
        // would eat most legitimate corrections.
        #expect(ScoredVerdict.evaluate(scores(-4.0, -3.5), thresholds: thresholds) == .accepted)
    }

    @Test func originalTextReadingBetterOverallVetoes() {
        // effect -> affect: similar means, but the whole text reads worse.
        #expect(ScoredVerdict.evaluate(scores(-12.6, -12.3, totals: (-30.0, -27.0)), thresholds: thresholds)
                == .rejected("totalOriginalMoreLikely"))
    }

    @Test func totalsOnlyCompareAtMatchedLengths() {
        // "your welcome btw" -> "You're welcome, btw.": three more tokens make
        // the replacement's total lower without making it worse.
        #expect(ScoredVerdict.evaluate(scores(-6.0, -7.0, totals: (-33.0, -21.0), counts: (6, 3)),
                                       thresholds: thresholds) == .accepted)
    }

    @Test func missingScoresSkipTheirChecks() {
        // Fail open: a check whose score couldn't be computed never rejects.
        #expect(ScoredVerdict.evaluate(scores(-2.0, nil), thresholds: thresholds) == .accepted)
        #expect(ScoredVerdict.evaluate(scores(nil, -1.0), thresholds: thresholds) == .accepted)
    }

    @Test func nonFiniteScoresAccept() {
        #expect(ScoredVerdict.evaluate(scores(.nan, -1.0), thresholds: thresholds) == .accepted)
        #expect(ScoredVerdict.evaluate(scores(-2.0, -5.0, totals: (.nan, -1.0)), thresholds: thresholds) == .accepted)
    }

    @Test func productionDefaultsMatchTheEvalTuning() {
        // gate_replay.py (2026-10-09): good fixes' total advantage for the
        // original peaks at +0.18; effect->affect +2.97, profanity +2.74.
        // Name swap Priya->Maya has mean margin 4.95; max good was 4.49.
        let tuned = ScoringThresholds()
        #expect(tuned.originalVetoMargin == 4.5)
        #expect(tuned.totalVetoMargin == 1.0)
        #expect(tuned.maxTokenCountDifferenceForTotals == 1)
    }
}

struct SpanTriageTests {
    private func span(_ original: String, _ replacement: String) -> EditDiff.Span {
        EditDiff.Span(anchor: "", original: original, replacement: replacement, suffix: "")
    }

    @Test func casingSpacingAndPunctuationAreCosmetic() {
        #expect(SpanTriage.isCosmetic(span("unit", "Unit")))
        #expect(SpanTriage.isCosmetic(span("some times", "sometimes")))
        #expect(SpanTriage.isCosmetic(span("However", "However,")))
    }

    @Test func wordChangesAreNotCosmetic() {
        #expect(!SpanTriage.isCosmetic(span("past", "passed")))
        #expect(!SpanTriage.isCosmetic(span("300", "00")))
        #expect(!SpanTriage.isCosmetic(span("cafés", "cafes")))
        #expect(!SpanTriage.isCosmetic(span("...", "!")))  // no letters: still scored
    }

    @Test func closeSpellingOfAMisspellingIsATypoFix() {
        #expect(SpanTriage.isTypoFix(span("resturant", "restaurant"),
                                     originalHasMisspelling: true, replacementHasMisspelling: false))
        #expect(SpanTriage.isTypoFix(span("the fucntion retuns", "The function returns"),
                                     originalHasMisspelling: true, replacementHasMisspelling: false))
    }

    @Test func swapsAndKeptMisspellingsAreNotTypoFixes() {
        // A misspelled original replaced by a different word is still scored.
        #expect(!SpanTriage.isTypoFix(span("Y'all ain't gonna", "You'll never"),
                                      originalHasMisspelling: true, replacementHasMisspelling: false))
        #expect(!SpanTriage.isTypoFix(span("past", "passed"),
                                      originalHasMisspelling: false, replacementHasMisspelling: false))
        #expect(!SpanTriage.isTypoFix(span("teh", "thhe"),
                                      originalHasMisspelling: true, replacementHasMisspelling: true))
    }
}
