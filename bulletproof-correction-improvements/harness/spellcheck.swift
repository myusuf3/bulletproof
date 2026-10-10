// Reads one word per line on stdin; prints the words NSSpellChecker flags,
// using the same call as bulletproof/Engines/SpellCheckGate.swift.
import AppKit
let checker = NSSpellChecker.shared
let tag = NSSpellChecker.uniqueSpellDocumentTag()
// Mirrors SpellCheckGate.firstMisspelled: on an English system, flagged only if both the
// US ("en") and British dictionaries flag the word; otherwise the automatic language.
let english = ["en", "en_GB"].filter(checker.availableLanguages.contains)
let languages: [String?] = checker.language().hasPrefix("en") && !english.isEmpty ? english : [nil]
while let line = readLine() {
    let w = line.trimmingCharacters(in: .whitespaces)
    if w.isEmpty { continue }
    if languages.allSatisfy({ checker.checkSpelling(of: w, startingAt: 0, language: $0, wrap: false,
                                                    inSpellDocumentWithTag: tag, wordCount: nil).location != NSNotFound }) {
        print(w)
    }
}
