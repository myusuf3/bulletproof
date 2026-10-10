import Foundation

/// Line breaks are layout the writer chose, but models sometimes join lines
/// while correcting (Apple Intelligence flattens emails and bullet lists:
/// "Hi Marcus,\n\nThanks" -> "Hi Marcus, thanks"). When the correction has
/// fewer line breaks than the original, put each lost break back in front of
/// the word that started that line, found by aligning the two texts' words.
/// Never adds breaks the original didn't have.
nonisolated enum LineBreakRestorer {
    static func restore(original: String, corrected: String) -> String {
        guard breaks(in: corrected) < breaks(in: original) else { return corrected }
        let source = WordTokens(original), output = WordTokens(corrected)
        guard !source.tokens.isEmpty, !output.tokens.isEmpty else { return corrected }

        let match = alignedPairs(source.keys, output.keys)
        var trailing = output.tokens.map(\.trailing)
        for (i, token) in source.tokens.enumerated().dropLast() where token.trailing.contains(where: \.isNewline) {
            // Anchor on the next line's first word; fall back to the word
            // before the break if that one was rewritten.
            if let j = match[i + 1], j > 0 {
                if !trailing[j - 1].contains(where: \.isNewline) { trailing[j - 1] = token.trailing }
            } else if let j = match[i], j < output.tokens.count - 1 {
                if !trailing[j].contains(where: \.isNewline) { trailing[j] = token.trailing }
            }
        }
        let rebuilt = output.leading + zip(output.tokens, trailing).map { $0.word + $1 }.joined()
        // Only accept a rebuild that ends with no more breaks than the original had.
        return breaks(in: rebuilt) <= breaks(in: original) ? rebuilt : corrected
    }

    private static func breaks(in text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNewline).count
    }

    /// Source word index -> output word index for words the LCS keeps,
    /// walked like EditDiff.spans.
    private static func alignedPairs(_ a: [String], _ b: [String]) -> [Int: Int] {
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var pairs: [Int: Int] = [:]
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                pairs[i] = j
                i += 1
                j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }
}

/// Whitespace-separated words with the whitespace after each, plus
/// case- and punctuation-free keys for alignment.
nonisolated struct WordTokens {
    struct Token {
        let word: String
        let trailing: String
    }

    let leading: String
    let tokens: [Token]
    var keys: [String] {
        tokens.map { String($0.word.lowercased().filter { $0.isLetter || $0.isNumber }) }
    }

    init(_ text: String) {
        var index = text.startIndex
        var leading = ""
        while index < text.endIndex, text[index].isWhitespace {
            leading.append(text[index])
            index = text.index(after: index)
        }
        var tokens: [Token] = []
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
            tokens.append(Token(word: word, trailing: trailing))
        }
        self.leading = leading
        self.tokens = tokens
    }
}
