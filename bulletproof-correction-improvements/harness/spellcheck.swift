// Reads one word per line on stdin; prints the words NSSpellChecker flags,
// using the same call as bulletproof/Engines/SpellCheckGate.swift.
import AppKit
let checker = NSSpellChecker.shared
let tag = NSSpellChecker.uniqueSpellDocumentTag()
while let line = readLine() {
    let w = line.trimmingCharacters(in: .whitespaces)
    if w.isEmpty { continue }
    if checker.checkSpelling(of: w, startingAt: 0, language: nil, wrap: false,
                             inSpellDocumentWithTag: tag, wordCount: nil).location != NSNotFound {
        print(w)
    }
}
