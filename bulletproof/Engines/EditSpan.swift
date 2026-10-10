import Foundation

/// Word-level diff between the user's text and the model's correction. Each
/// span carries the unchanged corrected-side text around it, so a scorer can
/// ask "how plausible is this replacement, right here" - and swap in the
/// original span for the counterfactual - and so deterministic rules can see
/// exactly which words an edit removed.
nonisolated enum EditDiff {
    struct Span: Equatable, Sendable {
        let anchor: String
        let original: String
        let replacement: String
        let suffix: String
    }

    static func spans(original: String, corrected: String) -> [Span] {
        let a = original.split(whereSeparator: \.isWhitespace).map(String.init)
        let b = corrected.split(whereSeparator: \.isWhitespace).map(String.init)

        // Longest-common-subsequence lengths; inputs are capped upstream at a
        // few hundred words, so the quadratic table stays small.
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }

        var spans: [Span] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                i += 1
                j += 1
                continue
            }
            let spanStart = j
            var originalRun: [String] = []
            var replacementRun: [String] = []
            while i < a.count || j < b.count {
                if i < a.count, j < b.count, a[i] == b[j] { break }
                if j == b.count || (i < a.count && lcs[i + 1][j] >= lcs[i][j + 1]) {
                    originalRun.append(a[i])
                    i += 1
                } else {
                    replacementRun.append(b[j])
                    j += 1
                }
            }
            spans.append(Span(anchor: b[..<spanStart].joined(separator: " "),
                              original: originalRun.joined(separator: " "),
                              replacement: replacementRun.joined(separator: " "),
                              suffix: b[j...].joined(separator: " ")))
        }
        return spans
    }
}

/// Retuned 2026-10-09 on the 400-case correction eval (both engines' outputs,
/// 1,218 spans, judged) plus the bench corpus and the probe's bad edits -
/// `bulletproof-correction-improvements/harness/gate_replay.py` replays it.
///
/// The old per-token *mean* floor (-12.0) vetoed 28 of 480 good outputs: a
/// misspelling splits into several subword pieces that predict each other,
/// so its mean beats the one rare token of the correct word ("resturant"
/// -6.27 vs "restaurant" -11.96). Real-word fixes and the bad swaps the floor
/// targeted overlap completely (past->passed -13.01, effect->affect -12.59),
/// so no floor separates them. Instead:
/// - typo-shaped spans skip scoring entirely (`SpanTriage`);
/// - `originalVetoMargin` (means) still catches name swaps (Priya->Maya, +4.95);
/// - the total log-prob of span + rest of text decides real-word swaps, but
///   only between length-matched versions - totals are biased toward fewer
///   tokens exactly as means are biased toward more. Good fixes peak at +0.18;
///   effect->affect +2.97, censored profanity +2.74, "300"->"00" +29.8.
/// Result: 1 of 480 good outputs vetoed (was 28), same bad catches.
nonisolated struct ScoringThresholds: Sendable {
    var originalVetoMargin = 4.5
    var totalVetoMargin = 1.0
    var maxTokenCountDifferenceForTotals = 1
}

nonisolated enum ScoredVerdict: Equatable, Sendable {
    case accepted
    case rejected(String)

    /// Fail open throughout: a missing or non-finite score never rejects -
    /// the gate is a veto layer, not a promoter.
    static func evaluate(_ scores: SpanScores, thresholds: ScoringThresholds) -> ScoredVerdict {
        guard let replacement = scores.replacement, replacement.isFinite else { return .accepted }
        if let original = scores.original, original.isFinite,
           original > replacement + thresholds.originalVetoMargin {
            return .rejected("originalMoreLikely")
        }
        if let replacementTotal = scores.replacementTotal, replacementTotal.isFinite,
           let originalTotal = scores.originalTotal, originalTotal.isFinite,
           let replacementCount = scores.replacementTokenCount,
           let originalCount = scores.originalTokenCount,
           abs(replacementCount - originalCount) <= thresholds.maxTokenCountDifferenceForTotals,
           originalTotal > replacementTotal + thresholds.totalVetoMargin {
            return .rejected("totalOriginalMoreLikely")
        }
        return .accepted
    }
}

/// Spans the scorer can't judge fairly and that can't be absurd swaps, so
/// they are accepted without scoring.
nonisolated enum SpanTriage {
    /// Same letters and digits, ignoring case: a casing, spacing or
    /// punctuation edit ("unit" -> "Unit", "some times" -> "sometimes").
    static func isCosmetic(_ span: EditDiff.Span) -> Bool {
        let original = letters(span.original)
        return !original.isEmpty && original == letters(span.replacement)
    }

    /// A non-word typo corrected to a close spelling: the original has a word
    /// the spell checker flags, the replacement has none, and the two are
    /// close edits of each other - so it isn't a swap to a different word.
    static func isTypoFix(_ span: EditDiff.Span, originalHasMisspelling: Bool,
                          replacementHasMisspelling: Bool) -> Bool {
        originalHasMisspelling && !replacementHasMisspelling
            && similarity(letters(span.original), letters(span.replacement)) >= minimumTypoSimilarity
    }

    static let minimumTypoSimilarity = 0.6

    /// 2 * LCS / (|a| + |b|) over characters.
    static func similarity(_ a: String, _ b: String) -> Double {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        var previous = Array(repeating: 0, count: b.count + 1)
        for x in a {
            var current = [0]
            for (j, y) in b.enumerated() {
                current.append(x == y ? previous[j] + 1 : max(previous[j + 1], current[j]))
            }
            previous = current
        }
        return 2 * Double(previous[b.count]) / Double(a.count + b.count)
    }

    private static func letters(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
