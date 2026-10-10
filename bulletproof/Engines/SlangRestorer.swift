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
        // Common chat and unit abbreviations (restore-only: they come back only
        // where the model wrote one of these exact expansions).
        "min": ["minute", "minutes"], "hr": ["hour", "hours"], "hrs": ["hours"],
        "approx": ["approximately"], "info": ["information"], "pic": ["picture", "photo"],
        "pics": ["pictures", "photos"], "convo": ["conversation"], "abt": ["about"], "cuz": ["because"],
        "ppl": ["people"], "prob": ["probably"], "tho": ["though", "although"], "thru": ["through"],
        "wk": ["week"], "wks": ["weeks"], "yr": ["year"], "yrs": ["years"], "esp": ["especially"],
        "appt": ["appointment"], "mtg": ["meeting"], "sec": ["second", "seconds"], "np": ["no problem"],
        "jk": ["just kidding"], "omg": ["oh my god", "oh my gosh"], "ttyl": ["talk to you later"],
        "hbu": ["how about you"], "wyd": ["what are you doing"], "rly": ["really"], "sry": ["sorry"],
        "msgs": ["messages"], "kk": ["okay"], "smol": ["small"],
        // Weekday and month abbreviations ("thurs" -> "Thursday").
        "mon": ["monday"], "tue": ["tuesday"], "tues": ["tuesday"], "wed": ["wednesday"],
        "thu": ["thursday"], "thur": ["thursday"], "thurs": ["thursday"], "fri": ["friday"],
        "sat": ["saturday"], "sun": ["sunday"], "jan": ["january"], "feb": ["february"], "aug": ["august"],
        "sep": ["september"], "sept": ["september"], "oct": ["october"], "nov": ["november"],
        "dec": ["december"],
    ]

    static func restore(original: String, corrected: String) -> String {
        let typed = WordTokens(original), output = WordTokens(corrected)
        guard !typed.tokens.isEmpty, !output.tokens.isEmpty else { return corrected }
        var words = output.tokens.map(\.word)
        var trailing = output.tokens.map(\.trailing)
        var removed = Set<Int>()
        let steps = WordAlignment.steps(typed.keys, output.keys)
        // A lowercase abbreviation the model only recased mid-sentence ("thurs" -> "Thurs",
        // "tbh" -> "TBH") gets the writer's casing back; sentence starts are left to the model.
        for case .kept(let i, let j) in steps {
            let typedWord = typed.tokens[i].word
            let core = String(typedWord.filter(\.isLetter))
            guard core.allSatisfy(\.isLowercase), table[core] != nil else { continue }
            let atSentenceStart = i == 0 || typed.tokens[i - 1].trailing.contains(where: \.isNewline)
                || typed.tokens[i - 1].word.last.map { ".!?:".contains($0) } == true
            let outputLetters = String(words[j].filter(\.isLetter))
            guard !atSentenceStart, outputLetters != core, outputLetters.lowercased() == core else { continue }
            var letters = core.makeIterator()
            words[j] = String(words[j].map { $0.isLetter ? (letters.next() ?? $0) : $0 })
        }
        for case .changed(let source, let outputRange) in steps {
            // Adjacent abbreviations change together ("u tmrw" -> "you tomorrow"),
            // so a changed run is split into one piece per typed word.
            guard (1...6).contains(source.count), !outputRange.isEmpty,
                  let pieces = split(source.map { typed.tokens[$0].word }, Array(words[outputRange])),
                  pieces.contains(where: { $0.restored != nil }) else { continue }
            var q = outputRange.lowerBound
            for piece in pieces {
                if let restored = piece.restored {
                    words[q] = restored
                    trailing[q] = trailing[q + piece.size - 1]
                    removed.formUnion((q + 1)..<(q + piece.size))
                }
                q += piece.size
            }
        }
        guard !removed.isEmpty || words != output.tokens.map(\.word) else { return corrected }
        return output.leading + words.indices.filter { !removed.contains($0) }
            .map { words[$0] + trailing[$0] }.joined()
    }

    /// One piece per typed word: an abbreviation takes 1-4 output words that
    /// spell one of its expansions; any other word takes exactly one.
    private static func split(_ typedWords: [String], _ outputWords: [String]) -> [(size: Int, restored: String?)]? {
        guard let first = typedWords.first else { return outputWords.isEmpty ? [] : nil }
        let rest = Array(typedWords.dropFirst())
        let maxSize = min(4, outputWords.count - rest.count)
        guard maxSize >= 1 else { return nil }
        for size in 1...maxSize {
            let restored = restoredPiece(typed: first, piece: outputWords.prefix(size))
            guard restored != nil || size == 1 else { continue }
            if let tail = split(rest, Array(outputWords.dropFirst(size))) {
                return [(size, restored)] + tail
            }
        }
        return nil
    }

    /// The typed abbreviation (with the piece's surrounding punctuation) when
    /// the piece is one of its expansions. The typed word may carry punctuation
    /// ("thx!", "idk,"): it matches on its letters, which must be one contiguous run.
    private static func restoredPiece(typed typedWord: String, piece: ArraySlice<String>) -> String? {
        let typedLetters = typedWord.drop(while: { !$0.isLetter }).reversed().drop(while: { !$0.isLetter }).reversed()
        let core = String(typedLetters).lowercased()
        guard !core.isEmpty, core.allSatisfy(\.isLetter), let expansions = table[core],
              (1...4).contains(piece.count) else { return nil }
        let phrase = piece.joined(separator: " ")
        let leading = String(phrase.prefix(while: { !$0.isLetter }))
        let tail = String(phrase.reversed().prefix(while: { !$0.isLetter && $0 != "'" }).reversed())
        let bare = phrase.dropFirst(leading.count).dropLast(tail.count)
        guard expansions.contains(bare.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")) else { return nil }
        return leading + String(typedLetters) + tail
    }
}
