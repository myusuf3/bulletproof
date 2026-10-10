// Mirrors SpellCheckGate.dictionary(forText:): one JSON string per stdin line ->
// the dictionary code for confidently non-English text, or "" for the English rule.
import AppKit
import NaturalLanguage
let available = NSSpellChecker.shared.availableLanguages
while let line = readLine() {
    guard let data = line.data(using: .utf8), let text = try? JSONDecoder().decode(String.self, from: data) else { print(""); continue }
    let r = NLLanguageRecognizer(); r.processString(text)
    guard let lang = r.dominantLanguage, lang != .english, (r.languageHypotheses(withMaximum: 1)[lang] ?? 0) >= 0.8 else { print(""); continue }
    print(available.first { $0 == lang.rawValue } ?? available.first { $0.hasPrefix(lang.rawValue + "_") } ?? "automatic")
}
