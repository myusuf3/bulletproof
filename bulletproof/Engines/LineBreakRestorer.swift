import Foundation

/// Line breaks are layout the writer chose, but models sometimes join lines
/// while correcting (Apple Intelligence flattens emails and bullet lists:
/// "Hi Marcus,\n\nThanks" -> "Hi Marcus, thanks"). When the correction has
/// fewer line breaks than the original, put each lost break back in front of
/// the word that started that line, found by aligning the two texts' words.
/// Symmetric: a break the model added between two words the original kept
/// on one line is removed (a correction never adds layout).
nonisolated enum LineBreakRestorer {
    static func restore(original: String, corrected: String) -> String {
        let source = WordTokens(original), output = WordTokens(corrected)
        guard source.tokens.count > 1, !output.tokens.isEmpty else { return corrected }

        let match = alignedPairs(source.keys, output.keys)
        var trailing = output.tokens.map(\.trailing)
        for (i, token) in source.tokens.enumerated().dropLast() {
            let wanted = newlines(token.trailing)
            if let j = match[i], match[i + 1] == j + 1 {
                // Neighbours aligned on both sides: the gap between them gets
                // the original's line breaks - restores joined lines and
                // removes breaks the model added ("\n\n" -> "\n" -> "\n\n").
                // Around a break, the gap is copied exactly: models also add
                // markdown hard-break spaces ("milk  \n"), invisible but a change.
                if newlines(trailing[j]) != wanted
                    || (wanted > 0 && trailing[j] != token.trailing) { trailing[j] = token.trailing }
            } else if wanted > 0 {
                // The break sits next to a rewritten word: anchor on the next
                // line's first word, else on the word before the break.
                let differs = { (gap: String) in newlines(gap) < wanted
                    || (newlines(gap) == wanted && gap != token.trailing) }
                if let j = match[i + 1], j > 0 {
                    if differs(trailing[j - 1]) { trailing[j - 1] = token.trailing }
                } else if let j = match[i], j < output.tokens.count - 1 {
                    if differs(trailing[j]) { trailing[j] = token.trailing }
                }
            }
        }
        let rebuilt = output.leading + zip(output.tokens, trailing).map { $0.word + $1 }.joined()
        // Only accept a rebuild that moves the break count toward the original's.
        return abs(breaks(in: rebuilt) - breaks(in: original)) <= abs(breaks(in: corrected) - breaks(in: original))
            ? rebuilt : corrected
    }

    private static func newlines(_ whitespace: String) -> Int {
        whitespace.filter(\.isNewline).count
    }

    private static func breaks(in text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNewline).count
    }

    /// Source word index -> output word index for words the alignment keeps.
    private static func alignedPairs(_ a: [String], _ b: [String]) -> [Int: Int] {
        var pairs: [Int: Int] = [:]
        for case .kept(let source, let output) in WordAlignment.steps(a, b) {
            pairs[source] = output
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
    /// Letters and numbers by Unicode scalar, so combining marks (Mn/Mc/Me)
    /// don't count: a reordered or changed Thai/Hindi vowel sign doesn't break
    /// alignment. Same keys as the harness's `isalnum` filter.
    var keys: [String] {
        tokens.map { token in
            var key = String.UnicodeScalarView()
            key.append(contentsOf: token.word.lowercased().unicodeScalars.filter { scalar in
                switch scalar.properties.generalCategory {
                case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                     .decimalNumber, .letterNumber, .otherNumber: true
                default: false
                }
            })
            return String(key)
        }
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

/// Word alignment shared by the restorers: the same LCS walk as
/// EditDiff.spans, over case- and punctuation-free keys, so neighbouring
/// casing or punctuation fixes don't merge into a changed run.
nonisolated enum WordAlignment {
    enum Step: Equatable {
        /// Source word `source` kept as output word `output`.
        case kept(source: Int, output: Int)
        /// Source words `source` replaced by output words `output` (either may be empty).
        case changed(source: Range<Int>, output: Range<Int>)
    }

    static func steps(_ a: [String], _ b: [String]) -> [Step] {
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var steps: [Step] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                steps.append(.kept(source: i, output: j))
                i += 1
                j += 1
                continue
            }
            let (i0, j0) = (i, j)
            while i < a.count || j < b.count {
                if i < a.count, j < b.count, a[i] == b[j] { break }
                if j == b.count || (i < a.count && lcs[i + 1][j] >= lcs[i][j + 1]) { i += 1 } else { j += 1 }
            }
            steps.append(.changed(source: i0..<i, output: j0..<j))
        }
        return steps
    }
}
