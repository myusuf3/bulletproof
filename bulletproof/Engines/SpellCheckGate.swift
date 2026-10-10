import AppKit

/// A proofread must never make spelling worse: any word the model
/// *introduced* that the system spell checker flags is a hallucination
/// signal. Main actor because NSSpellChecker.shared is not thread-safe.
/// Known limit: only non-words are caught (their/there passes).
@MainActor enum SpellCheckGate {
    /// Own document tag so ignored-word state never leaks between this gate
    /// and other NSSpellChecker.shared clients.
    private static let documentTag = NSSpellChecker.uniqueSpellDocumentTag()

    /// On an English system, a word is misspelled only if both the US and the
    /// British dictionary flag it: the models write American spelling, so the
    /// system's own variant (en_CA, en_GB) would reject correct fixes like
    /// "neigbor" -> "neighbor". The explicit dictionaries are also stricter than
    /// `language: nil`, whose per-word language guessing accepts "teh", "alot",
    /// "accomodate". Non-English systems keep the automatic behaviour.
    /// The spell checker's suggested spellings for a word (US and British).
    static func guesses(for word: String) -> [String] {
        let checker = NSSpellChecker.shared
        let range = NSRange(location: 0, length: (word as NSString).length)
        return ["en", "en_GB"].filter(checker.availableLanguages.contains).flatMap { language in
            checker.guesses(forWordRange: range, in: word, language: language,
                            inSpellDocumentWithTag: documentTag) ?? []
        }
    }

    static func firstMisspelled(in words: [String], language: String? = nil) -> String? {
        let checker = NSSpellChecker.shared
        let english: [String?] = ["en", "en_GB"].filter(checker.availableLanguages.contains)
        let automatic: [String?] = [nil]
        let languages: [String?] = language.map { [$0] }
            ?? (checker.language().hasPrefix("en") && !english.isEmpty ? english : automatic)
        return words.first { word in
            languages.allSatisfy { language in
                checker.checkSpelling(of: word, startingAt: 0, language: language,
                                      wrap: false, inSpellDocumentWithTag: documentTag,
                                      wordCount: nil).location != NSNotFound
            }
        }
    }
}
