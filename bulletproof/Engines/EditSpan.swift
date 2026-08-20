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

/// KeyType-seeded thresholds, explicitly provisional until tuned against the
/// benchmark corpus - they were calibrated for single words on base models,
/// and we score multi-word spans from instruct models.
nonisolated struct ScoringThresholds: Sendable {
    var minimumMeanLogProbability = -6.0
    var originalVetoMargin = 1.0
    var minimumSuffixMeanLogProbability = -7.0
}

nonisolated enum ScoredVerdict: Equatable, Sendable {
    case accepted
    case rejected(String)

    /// Fail open throughout: a missing or non-finite score never rejects -
    /// the gate is a veto layer, not a promoter.
    static func evaluate(replacementScore: Double, originalScore: Double?,
                         suffixScore: Double?, thresholds: ScoringThresholds) -> ScoredVerdict {
        guard replacementScore.isFinite else { return .accepted }
        if replacementScore < thresholds.minimumMeanLogProbability {
            return .rejected("belowFloor")
        }
        if let originalScore, originalScore.isFinite,
           originalScore > replacementScore + thresholds.originalVetoMargin {
            return .rejected("originalMoreLikely")
        }
        if let suffixScore, suffixScore.isFinite,
           suffixScore < thresholds.minimumSuffixMeanLogProbability {
            return .rejected("suffixBroken")
        }
        return .accepted
    }
}
