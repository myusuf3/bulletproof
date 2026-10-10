import Foundation

/// Chat abbreviations are the writer's style ("keep my style exactly"), but
/// models expand them while proofreading: `bc` -> `because`, `tbh` -> `to be
/// honest`. Where the user typed a known abbreviation and the correction
/// replaced exactly that word with one of its expansions, the abbreviation
/// comes back (with the replacement's surrounding punctuation). Only standard
/// chat abbreviations with unambiguous expansions are listed.
nonisolated enum SlangRestorer {
    private static let table: [String: [String]] = [
        "idk": ["i don't know", "i do not know", "i dont know"], "tbh": ["to be honest"],
        "ngl": ["not gonna lie", "not going to lie"], "imo": ["in my opinion"], "imho": ["in my humble opinion"],
        "btw": ["by the way"], "fyi": ["for your information"], "brb": ["be right back"], "omw": ["on my way"],
        "tmrw": ["tomorrow"], "tmr": ["tomorrow"], "thx": ["thanks", "thank you"], "thnx": ["thanks", "thank you"],
        "ty": ["thank you", "thanks"], "pls": ["please"], "plz": ["please"], "bc": ["because"], "rn": ["right now"],
        "u": ["you"], "ur": ["your", "you're", "you are"], "lmk": ["let me know"], "nvm": ["never mind"],
        "bday": ["birthday"], "msg": ["message"], "ok": ["okay"], "srsly": ["seriously"],
        "gonna": ["going to"], "wanna": ["want to"], "gotta": ["got to", "have to"], "kinda": ["kind of"],
        "sorta": ["sort of"], "lowkey": ["low-key", "low key"], "mins": ["minutes"], "secs": ["seconds"],
    ]

    static func restore(original: String, corrected: String) -> String {
        let typed = WordTokens(original), output = WordTokens(corrected)
        guard !typed.tokens.isEmpty, !output.tokens.isEmpty else { return corrected }
        let a = typed.keys, b = output.keys
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var words = output.tokens.map(\.word)
        var trailing = output.tokens.map(\.trailing)
        var removed = Set<Int>()
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                i += 1
                j += 1
                continue
            }
            let (i0, j0) = (i, j)
            while i < a.count || j < b.count {
                if i < a.count, j < b.count, a[i] == b[j] { break }
                if j == b.count || (i < a.count && lcs[i + 1][j] >= lcs[i][j + 1]) { i += 1 } else { j += 1 }
            }
            guard i - i0 == 1, (1...4).contains(j - j0) else { continue }
            // The typed word may carry punctuation ("thx!", "idk,"): match on its letters,
            // which must be one contiguous run, and keep the correction's punctuation.
            let typedWord = typed.tokens[i0].word
            let typedLetters = typedWord.drop(while: { !$0.isLetter }).reversed().drop(while: { !$0.isLetter }).reversed()
            let core = String(typedLetters).lowercased()
            guard !core.isEmpty, core.allSatisfy(\.isLetter), let expansions = table[core] else { continue }
            let typedCore = String(typedLetters)
            let phrase = words[j0..<j].joined(separator: " ")
            let leading = String(phrase.prefix(while: { !$0.isLetter }))
            let tail = String(phrase.reversed().prefix(while: { !$0.isLetter && $0 != "'" }).reversed())
            let bare = phrase.dropFirst(leading.count).dropLast(tail.count)
            guard expansions.contains(bare.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")) else { continue }
            words[j0] = leading + typedCore + tail
            trailing[j0] = trailing[j - 1]
            removed.formUnion((j0 + 1)..<j)
        }
        guard !removed.isEmpty || words != output.tokens.map(\.word) else { return corrected }
        return output.leading + words.indices.filter { !removed.contains($0) }
            .map { words[$0] + trailing[$0] }.joined()
    }
}
