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
    private let thresholds = ScoringThresholds()

    @Test func plausibleEditIsAccepted() {
        #expect(ScoredVerdict.evaluate(replacementScore: -2.0, originalScore: -5.0,
                                       suffixScore: -3.0, thresholds: thresholds) == .accepted)
    }

    @Test func implausibleReplacementFailsTheFloor() {
        #expect(ScoredVerdict.evaluate(replacementScore: -6.5, originalScore: -8.0,
                                       suffixScore: -3.0, thresholds: thresholds)
                == .rejected("belowFloor"))
    }

    @Test func originalReadingMuchBetterVetoesTheEdit() {
        // The "user wrote Jon on purpose" check: original clearly outscores
        // the replacement.
        #expect(ScoredVerdict.evaluate(replacementScore: -4.0, originalScore: -2.5,
                                       suffixScore: -3.0, thresholds: thresholds)
                == .rejected("originalMoreLikely"))
    }

    @Test func originalSlightlyBetterIsWithinTheMargin() {
        // Ties and small wins for the original are expected - vetoing them
        // would eat most legitimate corrections.
        #expect(ScoredVerdict.evaluate(replacementScore: -4.0, originalScore: -3.5,
                                       suffixScore: -3.0, thresholds: thresholds) == .accepted)
    }

    @Test func brokenContinuationFailsSuffixJoin() {
        #expect(ScoredVerdict.evaluate(replacementScore: -2.0, originalScore: -5.0,
                                       suffixScore: -7.5, thresholds: thresholds)
                == .rejected("suffixBroken"))
    }

    @Test func missingScoresSkipTheirChecks() {
        // Fail open: a check whose score couldn't be computed never rejects.
        #expect(ScoredVerdict.evaluate(replacementScore: -2.0, originalScore: nil,
                                       suffixScore: nil, thresholds: thresholds) == .accepted)
    }

    @Test func nonFiniteScoresAccept() {
        #expect(ScoredVerdict.evaluate(replacementScore: .nan, originalScore: -1.0,
                                       suffixScore: -1.0, thresholds: thresholds) == .accepted)
    }
}
