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
        let typed = original.split(whereSeparator: \.isWhitespace).map(String.init)
        let output = tokens(of: corrected)
        // Align on case- and punctuation-free keys so neighbouring casing or
        // punctuation fixes ("i dont" -> "I do not") don't merge into the run.
        let source = typed.map(alignmentKey), words = output.map { alignmentKey($0.word) }
        guard !source.isEmpty, !words.isEmpty else { return corrected }

        // Same LCS walk as EditDiff.spans, over the alignment keys.
        var lcs = Array(repeating: Array(repeating: 0, count: words.count + 1), count: source.count + 1)
        for i in stride(from: source.count - 1, through: 0, by: -1) {
            for j in stride(from: words.count - 1, through: 0, by: -1) {
                lcs[i][j] = source[i] == words[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var replacements: [(range: Range<Int>, text: String)] = []
        var i = 0, j = 0
        while i < source.count || j < words.count {
            if i < source.count, j < words.count, source[i] == words[j] {
                i += 1
                j += 1
                continue
            }
            let originalStart = i, outputStart = j
            while i < source.count || j < words.count {
                if i < source.count, j < words.count, source[i] == words[j] { break }
                if j == words.count || (i < source.count && lcs[i + 1][j] >= lcs[i][j + 1]) {
                    i += 1
                } else {
                    j += 1
                }
            }
            if i - originalStart == 1, let text = contraction(typed: typed[originalStart],
                                                              expansion: output[outputStart..<j].map(\.word)) {
                replacements.append((outputStart..<j, text))
            }
        }
        guard !replacements.isEmpty else { return corrected }

        var result = ""
        var index = 0
        for replacement in replacements {
            for token in output[index..<replacement.range.lowerBound] {
                result += token.word + token.trailing
            }
            result += replacement.text + output[replacement.range.upperBound - 1].trailing
            index = replacement.range.upperBound
        }
        for token in output[index...] {
            result += token.word + token.trailing
        }
        return output[0].leading + result
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

    private static func alignmentKey(_ word: String) -> String {
        String(word.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private struct Token {
        let leading: String
        let word: String
        let trailing: String
    }

    /// Words with the whitespace after each, so line breaks survive the rebuild.
    /// Only the first token carries leading whitespace.
    private static func tokens(of text: String) -> [Token] {
        var result: [Token] = []
        var leading = ""
        var index = text.startIndex
        while index < text.endIndex, text[index].isWhitespace {
            leading.append(text[index])
            index = text.index(after: index)
        }
        while index < text.endIndex {
            var word = ""
            while index < text.endIndex, !text[index].isWhitespace {
                word.append(text[index])
                index = text.index(after: index)
            }
            var trailing = ""
            while index < text.endIndex, text[index].isWhitespace {
                trailing.append(text[index])
                index = text.index(after: index)
            }
            result.append(Token(leading: result.isEmpty ? leading : "", word: word, trailing: trailing))
        }
        return result
    }
}
