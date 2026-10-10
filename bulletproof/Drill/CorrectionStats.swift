import Foundation

/// Counts the user's recurring one-word typos (typo -> fix) from accepted
/// corrections - the raw material for the daily practice drill. Stores
/// single lowercased words only, never sentences: the same privacy line as
/// the personal vocabulary.
@MainActor final class CorrectionStats {
    static let shared = CorrectionStats()

    struct Entry: Codable, Equatable {
        var fix: String
        var count: Int
    }

    private static let key = "correctionStats"
    private static let cap = 300
    /// Seen twice means a habit, not a slip - the same signal the personal
    /// vocabulary uses to promote a word.
    private static let recurringThreshold = 2

    private let defaults: UserDefaults
    private let isMisspelled: (String) -> Bool
    private var entries: [String: Entry]

    init(defaults: UserDefaults = .standard, isMisspelled: ((String) -> Bool)? = nil) {
        self.defaults = defaults
        self.isMisspelled = isMisspelled ?? { SpellCheckGate.firstMisspelled(in: [$0]) != nil }
        entries = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    var trackedCount: Int { entries.count }

    func record(original: String, corrected: String) {
        var seenNow: Set<String> = []
        for span in EditDiff.spans(original: original, corrected: corrected) {
            guard let typo = Self.drillableWord(span.original),
                  let fix = Self.drillableWord(span.replacement),
                  typo != fix, isTypo(typo, fixedTo: fix) else { continue }
            var entry = entries[typo] ?? Entry(fix: fix, count: 0)
            entry.count += 1
            entry.fix = fix
            entries[typo] = entry
            seenNow.insert(typo)
        }
        guard !seenNow.isEmpty else { return }
        // Never evict what this call just saw: a table full of count >= 2
        // entries would otherwise delete every newcomer at count 1 in the
        // same call, freezing the tracked set forever.
        while entries.count > Self.cap {
            let weakest = entries
                .filter { !seenNow.contains($0.key) }
                .min { ($0.value.count, $0.key) < ($1.value.count, $1.key) }
            guard let weakest else { break }
            entries[weakest.key] = nil
        }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// Recurring typos only - a one-off slip is not drill material.
    func topFixes(limit: Int) -> [(typo: String, fix: String, count: Int)] {
        entries.filter { $0.value.count >= Self.recurringThreshold }
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .prefix(limit)
            .map { ($0.key, $0.value.fix, $0.value.count) }
    }

    /// Typing slips, not model rewrites. Real usage drilled "understood ->
    /// understand" x7 (a tense rewrite of a correct word); a pair counts only if
    /// the typed word is misspelled, differs only by an apostrophe (dont/don't),
    /// sounds the same (their/there, weak/week), or is a one-letter slip in a
    /// longer word (exited/excited). Grammar and tense rewrites between two real
    /// words (know/knows, was/were, til/until) aren't practice material.
    func isTypo(_ typo: String, fixedTo fix: String) -> Bool {
        if isMisspelled(typo) { return true }
        let bare = { (w: String) in w.filter { !"'\u{2019}".contains($0) } }
        if bare(typo) == bare(fix) { return true }
        if Self.soundSkeleton(typo) == Self.soundSkeleton(fix) { return true }
        return typo.count >= 5 && fix.count >= 5 && Self.isOneEditApart(typo, fix)
    }

    /// Consonant skeleton with a few English spelling equivalences, so
    /// homophones collide: their/there -> "thr", right/write -> "rt".
    static func soundSkeleton(_ word: String) -> String {
        var w = word.lowercased().filter { !"'\u{2019}".contains($0) }
        for (from, to) in [("wh", "w"), ("wr", "r"), ("kn", "n"), ("gh", ""), ("ph", "f"),
                           ("ck", "k"), ("x", "ks"), ("c", "k"), ("q", "k")] {
            w = w.replacingOccurrences(of: from, with: to)
        }
        var skeleton = ""
        for c in w where !"aeiouy".contains(c) && skeleton.last != c {
            skeleton.append(c)
        }
        if skeleton.hasPrefix("tw") { skeleton.remove(at: skeleton.index(after: skeleton.startIndex)) }
        return skeleton
    }

    private static func isOneEditApart(_ a: String, _ b: String) -> Bool {
        let a = Array(a), b = Array(b)
        guard abs(a.count - b.count) <= 1 else { return false }
        var i = 0, j = 0, edits = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] { i += 1; j += 1; continue }
            edits += 1
            if edits > 1 { return false }
            if a.count > b.count { i += 1 } else if b.count > a.count { j += 1 } else { i += 1; j += 1 }
        }
        return edits + (a.count - i) + (b.count - j) <= 1
    }

    /// A drillable typo is a clean single-word substitution: one alphabetic
    /// word on each side (contractions allowed), no stray punctuation, and
    /// not a capitalization-only change.
    private static func drillableWord(_ text: String) -> String? {
        let tokens = OutputGate.wordTokens(in: text)
        guard tokens.count == 1, let word = tokens.first,
              text.trimmingCharacters(in: .whitespaces) == word,
              word.count >= 2,
              word.filter({ !"''".contains($0) }).allSatisfy(\.isLetter) else {
            return nil
        }
        return word.lowercased()
    }
}
