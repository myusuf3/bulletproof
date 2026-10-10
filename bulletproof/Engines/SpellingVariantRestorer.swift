import Foundation

/// British (and Commonwealth) spellings are the writer's style, not errors,
/// but models Americanize them ("colour" -> "color", "favourite" ->
/// "favorite"). Where the writer typed a listed British form and the model
/// replaced exactly that word with its American form, the writer's spelling
/// comes back (with the output's capitalization). A curated table, not
/// suffix rules: "four" -> "for" or "filled" -> "filed" are real fixes.
nonisolated enum SpellingVariantRestorer {
    static let table: [String: String] = {
        var t: [String: String] = [
            "grey": "gray", "greys": "grays", "cheque": "check", "cheques": "checks", "programme": "program",
            "programmes": "programs", "mould": "mold", "plough": "plow", "aluminium": "aluminum", "tyre": "tire",
            "tyres": "tires", "kerb": "curb", "sceptic": "skeptic", "sceptical": "skeptical", "jewellery": "jewelry",
            "pyjamas": "pajamas", "manoeuvre": "maneuver", "catalogue": "catalog", "dialogue": "dialog",
            "analogue": "analog", "enrol": "enroll", "enrolment": "enrollment", "fulfil": "fulfill",
            "fulfilment": "fulfillment", "instalment": "installment", "judgement": "judgment", "ageing": "aging",
            "licence": "license", "defence": "defense", "offence": "offense", "pretence": "pretense",
            "practise": "practice", "marvellous": "marvelous", "woollen": "woolen", "towards": "toward",
            "whilst": "while", "amongst": "among",
        ]
        let our = ["colour", "favour", "flavour", "honour", "humour", "labour", "neighbour", "harbour", "rumour",
                   "vapour", "vigour", "behaviour", "endeavour", "savour", "odour", "armour", "clamour", "glamour",
                   "parlour", "saviour", "splendour", "tumour", "valour"]
        for word in our {
            let stem = String(word.dropLast(3))
            for suffix in ["", "s", "ed", "ing", "ite", "ites", "able", "ably", "er", "ers", "ful", "less"] {
                t[word + suffix] = stem + "or" + suffix
            }
        }
        let ise = ["organis", "realis", "recognis", "apologis", "analys", "emphasis", "criticis", "prioritis",
                   "summaris", "categoris", "authoris", "customis", "minimis", "maximis", "optimis", "finalis",
                   "standardis", "memoris", "utilis", "visualis", "mobilis", "personalis", "specialis",
                   "familiaris", "paralys", "catalys"]
        for stem in ise {
            let american = String(stem.dropLast()) + "z"
            for suffix in ["e", "es", "ed", "ing", "ation", "ations", "er", "ers"] {
                t[stem + suffix] = american + suffix
            }
        }
        for word in ["centre", "metre", "litre", "theatre", "fibre", "calibre", "sombre", "spectre", "lustre", "meagre"] {
            let stem = String(word.dropLast(2))
            t[word] = stem + "er"
            t[word + "s"] = stem + "ers"
        }
        for stem in ["travel", "cancel", "label", "model", "level", "fuel", "total", "signal", "channel", "dial",
                     "marvel", "counsel", "jewel", "shovel", "tunnel"] {
            for suffix in ["ed", "ing", "er", "ers"] {
                t[stem + "l" + suffix] = stem + suffix
            }
        }
        return t
    }()

    static func restore(original: String, corrected: String) -> String {
        let typed = WordTokens(original), output = WordTokens(corrected)
        guard !typed.tokens.isEmpty, !output.tokens.isEmpty else { return corrected }
        var words = output.tokens.map(\.word)
        // Equal-length changed runs pair one to one ("favourite flavour" -> "favorite flavor").
        let pairs = WordAlignment.steps(typed.keys, output.keys).flatMap { step -> [(Int, Int)] in
            guard case .changed(let source, let outputRange) = step, source.count == outputRange.count else { return [] }
            return Array(zip(source, outputRange))
        }
        for (i, j) in pairs {
            let typedLetters = String(typed.tokens[i].word.filter(\.isLetter))
            let outputWord = words[j]
            let outputLetters = String(outputWord.filter(\.isLetter))
            guard let american = table[typedLetters.lowercased()], american == outputLetters.lowercased() else { continue }
            // Writer's letters, output's capitalization of the first letter, output's punctuation.
            var british = typedLetters.lowercased()
            if outputLetters.first?.isUppercase == true { british = british.prefix(1).uppercased() + british.dropFirst() }
            if outputLetters.count > 1, outputLetters.allSatisfy({ $0.isUppercase }) { british = british.uppercased() }
            let leading = outputWord.prefix(while: { !$0.isLetter }), trailing = outputWord.reversed().prefix(while: { !$0.isLetter })
            words[j] = leading + british + String(trailing.reversed())
        }
        guard words != output.tokens.map(\.word) else { return corrected }
        return output.leading + zip(words, output.tokens).map { $0 + $1.trailing }.joined()
    }
}
