import AppKit

/// A proofread must never make spelling worse: any word the model
/// *introduced* that the system spell checker flags is a hallucination
/// signal. Main actor because NSSpellChecker.shared is not thread-safe.
/// Known limit: only non-words are caught (their/there passes).
@MainActor enum SpellCheckGate {
    /// Own document tag so ignored-word state never leaks between this gate
    /// and other NSSpellChecker.shared clients.
    private static let documentTag = NSSpellChecker.uniqueSpellDocumentTag()

    static func firstMisspelled(in words: [String], language: String? = nil) -> String? {
        let checker = NSSpellChecker.shared
        return words.first { word in
            checker.checkSpelling(of: word, startingAt: 0, language: language,
                                  wrap: false, inSpellDocumentWithTag: documentTag,
                                  wordCount: nil).location != NSNotFound
        }
    }
}
