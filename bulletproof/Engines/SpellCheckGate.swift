import AppKit
import NaturalLanguage

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

    /// Dictionary for text that is confidently *not* English (fr, es, pt_BR...):
    /// on an English system the US/British rule would flag every correct
    /// non-English word the model writes ("très", "útil") as a misspelling.
    /// nil means "English (or unsure): use the default rule". Decided on the
    /// corrected text, which is cleaner than the typo-laden input.
    static func dictionary(forText text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage, language != .english,
              (recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0) >= 0.8 else { return nil }
        let available = NSSpellChecker.shared.availableLanguages
        return available.first { $0 == language.rawValue }
            ?? available.first { $0.hasPrefix(language.rawValue + "_") }
            ?? automaticLanguage
    }

    /// Pass as `language` to use the system's per-word automatic detection.
    static let automaticLanguage = "automatic"

    static func firstMisspelled(in words: [String], language: String? = nil) -> String? {
        let checker = NSSpellChecker.shared
        let english: [String?] = ["en", "en_GB"].filter(checker.availableLanguages.contains)
        let automatic: [String?] = [nil]
        let languages: [String?] = language.map { $0 == automaticLanguage ? automatic : [$0] }
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
