import Foundation

/// The writer's contractions are style ("keep my style exactly"), but models
/// expand them while fixing the apostrophe: `wasnt` -> `was not` instead of
/// `wasn't`, `Its` -> `It is`. Where the user typed a contraction (with or
/// without its apostrophe) and the correction aligns that one word to its
/// expansion, put the contraction back, apostrophe included. Expansions the
/// user wrote themselves are never touched - only aligned replacements of a
/// contraction-shaped input word.
nonisolated enum ContractionRestorer {
    /// Letters-only lowercased key -> (contraction, its expansions).
    private static let table: [String: (String, [String])] = {
        let rows: [(String, [String])] = [
            ("don't", ["do not"]), ("doesn't", ["does not"]), ("didn't", ["did not"]),
            ("can't", ["cannot", "can not"]), ("won't", ["will not"]), ("isn't", ["is not"]),
            ("aren't", ["are not"]), ("wasn't", ["was not"]), ("weren't", ["were not"]),
            ("haven't", ["have not"]), ("hasn't", ["has not"]), ("hadn't", ["had not"]),
            ("wouldn't", ["would not"]), ("shouldn't", ["should not"]), ("couldn't", ["could not"]),
            ("mustn't", ["must not"]), ("needn't", ["need not"]),
            ("it's", ["it is", "it has"]), ("that's", ["that is", "that has"]),
            ("there's", ["there is", "there has"]), ("what's", ["what is", "what has"]),
            ("here's", ["here is"]), ("who's", ["who is", "who has"]),
            ("he's", ["he is", "he has"]), ("she's", ["she is", "she has"]),
            ("let's", ["let us"]),
            ("I'm", ["i am"]), ("I've", ["i have"]), ("I'll", ["i will"]), ("I'd", ["i would", "i had"]),
            ("you're", ["you are"]), ("you've", ["you have"]), ("you'll", ["you will"]), ("you'd", ["you would", "you had"]),
            ("we're", ["we are"]), ("we've", ["we have"]), ("we'll", ["we will"]),
            ("they're", ["they are"]), ("they've", ["they have"]), ("they'll", ["they will"]), ("they'd", ["they would", "they had"]),
        ]
        return Dictionary(uniqueKeysWithValues: rows.map { (key(for: $0.0), ($0.0, $0.1)) })
    }()

    static func restore(original: String, corrected: String) -> String {
        let typed = WordTokens(original), output = WordTokens(corrected)
        guard !typed.tokens.isEmpty, !output.tokens.isEmpty else { return corrected }
        var replacements: [(range: Range<Int>, text: String)] = []
        for case .changed(let source, let outputRange) in WordAlignment.steps(typed.keys, output.keys)
        where source.count == 1 {
            if let text = contraction(typed: typed.tokens[source.lowerBound].word,
                                      expansion: output.tokens[outputRange].map(\.word)) {
                replacements.append((outputRange, text))
            }
        }
        guard !replacements.isEmpty else { return corrected }

        var result = output.leading
        var index = 0
        for replacement in replacements {
            for token in output.tokens[index..<replacement.range.lowerBound] {
                result += token.word + token.trailing
            }
            result += replacement.text + output.tokens[replacement.range.upperBound - 1].trailing
            index = replacement.range.upperBound
        }
        for token in output.tokens[index...] {
            result += token.word + token.trailing
        }
        return result
    }

    /// The contraction for a typed contraction-shaped word whose aligned
    /// replacement is one of its expansions, cased and punctuated like the
    /// replacement (`It is,` -> `It's,`).
    private static func contraction(typed: String, expansion: [String]) -> String? {
        guard (1...2).contains(expansion.count),
              let (contracted, expansions) = table[key(for: typed)] else { return nil }
        let trailingPunctuation = String(expansion.last!.reversed().prefix(while: { !$0.isLetter }).reversed())
        let leadingPunctuation = String(expansion.first!.prefix(while: { !$0.isLetter }))
        let phrase = expansion.joined(separator: " ")
        let bare = phrase.dropFirst(leadingPunctuation.count).dropLast(trailingPunctuation.count)
        guard !bare.isEmpty, expansions.contains(bare.lowercased()),
              bare.allSatisfy({ $0.isLetter || $0 == " " }) else { return nil }
        var text = contracted
        if bare.first!.isUppercase, let first = text.first, first.isLowercase {
            text = first.uppercased() + text.dropFirst()
        }
        return leadingPunctuation + text + trailingPunctuation
    }

    private static func key(for word: String) -> String {
        String(word.lowercased().filter(\.isLetter))
    }
}
