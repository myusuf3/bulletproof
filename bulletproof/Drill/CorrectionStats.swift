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
    private var entries: [String: Entry]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    var trackedCount: Int { entries.count }

    func record(original: String, corrected: String) {
        var seenNow: Set<String> = []
        for span in EditDiff.spans(original: original, corrected: corrected) {
            guard let typo = Self.drillableWord(span.original),
                  let fix = Self.drillableWord(span.replacement),
                  typo != fix else { continue }
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
