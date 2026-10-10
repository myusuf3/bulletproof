import Foundation

/// Contractions typed without their apostrophe ("Im", "dont", "wasnt") are
/// typos the user wants fixed, and the models sometimes leave them. Only the
/// spellings that can't be a real word are fixed - `cant`, `wont`, `were`,
/// `well`, `ill`, `its`, `lets`, `id`, `hell`, `shell` and `wed` are all
/// words, so they're left to the model. Misplaced apostrophes ("would'nt")
/// are fixed the same way. Code spans are never touched.
nonisolated enum ApostropheFixer {
    private static let fixes: [String: String] = {
        let forms = ["don't", "doesn't", "didn't", "isn't", "aren't", "wasn't", "weren't", "haven't",
                     "hasn't", "hadn't", "wouldn't", "shouldn't", "couldn't", "mustn't", "needn't",
                     "I'm", "I've", "you're", "you've", "you'll", "they're", "they've", "they'll",
                     "that's", "there's", "what's", "who's", "we've",
                     "would've", "should've", "could've"]
        return Dictionary(uniqueKeysWithValues: forms.map { ($0.lowercased().filter(\.isLetter), $0) })
    }()

    /// Misplaced apostrophes in "n't" contractions ("would'nt", "does'nt",
    /// "ca'nt") and the model's own half-fix of them ("would't"). None is a word.
    /// The dropped-n form is only matched for longer stems ("is't" and "do't" are left alone).
    private static let misplaced: [String: String] = {
        let forms = ["don't", "doesn't", "didn't", "isn't", "aren't", "wasn't", "weren't", "haven't",
                     "hasn't", "hadn't", "wouldn't", "shouldn't", "couldn't", "mustn't", "needn't",
                     "can't", "won't", "shan't", "ain't"]
        var map: [String: String] = [:]
        for form in forms {
            let stem = String(form.dropLast(3))
            map[stem + "'nt"] = form
            if stem.count > 2 { map[stem + "'t"] = form }
        }
        return map
    }()

    static func fix(_ text: String) -> String {
        let code = CodeSpanRestorer.spans(in: text)
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isLetter else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }
            let start = index
            while index < text.endIndex, text[index].isLetter || text[index] == "'" || text[index] == "\u{2019}" {
                index = text.index(after: index)
            }
            let word = String(text[start..<index])
            // Whole words only: a letter or digit right after (e.g. "dont2") means it's not one.
            let followedByWordChar = index < text.endIndex && (text[index].isNumber || text[index] == "_")
            let precededByWordChar = start > text.startIndex
                && { let c = text[text.index(before: start)]; return c.isNumber || c == "_" || c == "@" || c == "#" }()
            let insideCode = code.contains { $0.contains(start) }
            if !followedByWordChar, !precededByWordChar, !insideCode,
               !word.contains("'"), !word.contains("\u{2019}"), let fixed = fixes[word.lowercased()] {
                result += cased(fixed, like: word)
            } else if !followedByWordChar, !precededByWordChar, !insideCode,
                      let fixed = misplaced[word.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")] {
                // Keep the writer's apostrophe style (curly stays curly).
                let mark = word.contains("\u{2019}") ? "\u{2019}" : "'"
                result += cased(fixed, like: word).replacingOccurrences(of: "'", with: mark)
            } else {
                result += word
            }
        }
        return result
    }

    /// "Dont" -> "Don't", "DONT" -> "DON'T", "dont" -> "don't"; "I" stays capital.
    private static func cased(_ fixed: String, like typed: String) -> String {
        if typed.count > 1, typed.allSatisfy({ !$0.isLetter || $0.isUppercase }) { return fixed.uppercased() }
        if typed.first?.isUppercase == true { return fixed.prefix(1).uppercased() + fixed.dropFirst() }
        return fixed
    }
}
