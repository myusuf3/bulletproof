// Reads one word per line on stdin; prints the words NSSpellChecker flags,
// using the same call as bulletproof/Engines/SpellCheckGate.swift.
import AppKit
let checker = NSSpellChecker.shared
let tag = NSSpellChecker.uniqueSpellDocumentTag()
// Mirrors SpellCheckGate.firstMisspelled: on an English system, flagged only if both the
// US ("en") and British dictionaries flag the word; otherwise the automatic language.
// Optional argv[1]: a dictionary code from langdet, or "automatic" (SpellCheckGate's language parameter).
let english: [String?] = ["en", "en_GB"].filter(checker.availableLanguages.contains)
let automatic: [String?] = [nil]
let forced: String? = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil
let languages: [String?] = forced.map { $0 == "automatic" ? automatic : [$0] }
    ?? (checker.language().hasPrefix("en") && !english.isEmpty ? english : automatic)
while let line = readLine() {
    let w = line.trimmingCharacters(in: .whitespaces)
    if w.isEmpty { continue }
    if languages.allSatisfy({ checker.checkSpelling(of: w, startingAt: 0, language: $0, wrap: false,
                                                    inSpellDocumentWithTag: tag, wordCount: nil).location != NSNotFound }) {
        print(w)
    }
}
