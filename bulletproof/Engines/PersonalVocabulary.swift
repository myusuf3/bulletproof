import Foundation

/// Words the user demonstrably types on purpose - names, jargon, brands -
/// learned from proofread inputs: a word the spell checker doesn't know,
/// seen in two separate proofreads, is intentional. Stores single lowercased
/// words only, never sentences - nothing on disk can reconstruct what the
/// user wrote. Feeds the spell-check gate now; later the scored gate's
/// protect-list. Main actor because the default unknown-word check is
/// NSSpellChecker.
@MainActor final class PersonalVocabulary {
    static let shared = PersonalVocabulary()

    private static let wordsKey = "personalVocabularyWords"
    private static let countsKey = "personalVocabularyCounts"
    private static let promotionThreshold = 2
    private static let wordCap = 500
    private static let pendingCap = 1000

    private let defaults: UserDefaults
    private let isUnknownWord: (String) -> Bool
    private(set) var words: Set<String>
    private var pendingCounts: [String: Int]

    init(defaults: UserDefaults = .standard, isUnknownWord: ((String) -> Bool)? = nil) {
        self.defaults = defaults
        self.isUnknownWord = isUnknownWord ?? { SpellCheckGate.firstMisspelled(in: [$0]) != nil }
        words = Set(defaults.stringArray(forKey: Self.wordsKey) ?? [])
        pendingCounts = defaults.dictionary(forKey: Self.countsKey) as? [String: Int] ?? [:]
    }

    func observe(_ input: String) {
        var changed = false
        // Unique per observation: pasting "Priya Priya Priya" is one sighting.
        for word in Set(Self.candidateWords(in: input)) {
            let key = word.lowercased()
            guard !words.contains(key), isUnknownWord(word) else { continue }
            changed = true
            let count = (pendingCounts[key] ?? 0) + 1
            if count >= Self.promotionThreshold {
                pendingCounts[key] = nil
                if words.count < Self.wordCap {
                    words.insert(key)
                }
            } else {
                if pendingCounts.count >= Self.pendingCap,
                   let victim = pendingCounts.first(where: { $0.value <= 1 })?.key {
                    pendingCounts[victim] = nil
                }
                pendingCounts[key] = count
            }
        }
        if changed {
            defaults.set(Array(words), forKey: Self.wordsKey)
            defaults.set(pendingCounts, forKey: Self.countsKey)
        }
    }

    func contains(_ word: String) -> Bool {
        words.contains(word.lowercased())
    }

    /// Same shape the spell-check gate checks: whole alphabetic words of 3+
    /// letters, contractions intact.
    private static func candidateWords(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && !"''".contains($0) })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "''")) }
            .filter { word in
                let bare = word.filter { !"''".contains($0) }
                return bare.count >= 3 && bare.allSatisfy(\.isLetter)
            }
    }
}
