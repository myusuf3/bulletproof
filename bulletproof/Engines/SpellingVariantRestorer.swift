import Foundation

/// British (and Commonwealth) spellings are the writer's style, not errors,
/// but models Americanize them ("colour" -> "color", "favourite" ->
/// "favorite"). Where the writer typed a listed British form and the model
/// replaced exactly that word with its American form, the writer's spelling
/// comes back (with the output's capitalization), and so does a dropped-g
/// form ("fixin'" -> "fixing" -> "fixin'"). A curated table, not
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

    /// Letter runs: "looong" -> [(l,1),(o,3),(n,1),(g,1)].
    private static func runs(_ letters: String) -> [(Character, Int)] {
        var result: [(Character, Int)] = []
        for character in letters.lowercased() {
            if let last = result.last, last.0 == character { result[result.count - 1].1 += 1 } else { result.append((character, 1)) }
        }
        return result
    }

    /// An elongation the model shortened: a run of 3+ letters written once in the
    /// output ("looong" -> "long", "noooo" -> "no"), every other run identical.
    /// A tripled letter written twice is a typo of a double ("offfice" -> "office").
    static func isShortenedElongation(typed: String, output: String) -> Bool {
        let a = runs(typed), b = runs(output)
        guard a.count == b.count, a.contains(where: { $0.1 >= 3 }) else { return false }
        return zip(a, b).allSatisfy { x, y in x.0 == y.0 && (x.1 >= 3 ? y.1 == 1 : y.1 == x.1) }
    }

    /// Capitals the writer chose on purpose: ALL CAPS (2+ letters) or an internal
    /// capital (sUrE, iPhone, NASA).
    private static func hasDeliberateCase(_ letters: String) -> Bool {
        letters.count >= 2 && (letters.allSatisfy(\.isUppercase) || letters.dropFirst().contains(where: \.isUppercase))
    }

    private static func rebuilt(_ outputWord: String, letters: String) -> String {
        let leading = outputWord.prefix(while: { !$0.isLetter })
        let trailing = String(outputWord.reversed().prefix(while: { !$0.isLetter }).reversed())
        return leading + letters + trailing
    }

    static func restore(original: String, corrected: String) -> String {
        let typed = WordTokens(original), output = WordTokens(corrected)
        guard !typed.tokens.isEmpty, !output.tokens.isEmpty else { return corrected }
        var words = output.tokens.map(\.word)
        let steps = WordAlignment.steps(typed.keys, output.keys)
        // Deliberate capitals the model only recased ("sUrE" -> "sure", "WHY" -> "why") come back.
        for case .kept(let i, let j) in steps {
            let typedLetters = String(typed.tokens[i].word.filter(\.isLetter))
            let outputLetters = String(words[j].filter(\.isLetter))
            if hasDeliberateCase(typedLetters), outputLetters != typedLetters, outputLetters.lowercased() == typedLetters.lowercased() {
                words[j] = rebuilt(words[j], letters: typedLetters)
            }
        }
        // Equal-length changed runs pair one to one ("favourite flavour" -> "favorite flavor").
        let pairs = steps.flatMap { step -> [(Int, Int)] in
            guard case .changed(let source, let outputRange) = step, source.count == outputRange.count else { return [] }
            return Array(zip(source, outputRange))
        }
        for (i, j) in pairs {
            let typedLetters = String(typed.tokens[i].word.filter(\.isLetter))
            let outputWord = words[j]
            let outputLetters = String(outputWord.filter(\.isLetter))
            // A word the writer typed in ALL CAPS keeps caps when corrected ("TEH" -> "the" -> "THE").
            if typedLetters.count >= 2, typedLetters.allSatisfy(\.isUppercase), outputLetters.contains(where: \.isLowercase) {
                words[j] = rebuilt(outputWord, letters: outputLetters.uppercased())
                continue
            }
            // An elongation the model shortened comes back ("looong" -> "long" -> "looong").
            if !typedLetters.isEmpty, !outputLetters.isEmpty, isShortenedElongation(typed: typedLetters, output: outputLetters) {
                let form = outputLetters.first?.isUppercase == true && typedLetters.first?.isUppercase != true
                    ? typedLetters.prefix(1).uppercased() + typedLetters.dropFirst() : typedLetters
                words[j] = rebuilt(outputWord, letters: form)
                continue
            }
            var typedWord = typed.tokens[i].word.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            while let last = typedWord.last, ".,;:!?)\"".contains(last) { typedWord.removeLast() }
            // Dropped-g forms are the writer's voice: "fixin'" written as "fixing" comes back.
            if typedWord.hasSuffix("in'"), typedLetters.count >= 4, outputLetters.lowercased() == typedLetters.lowercased() + "g" {
                let leading = outputWord.prefix(while: { !$0.isLetter })
                var trailing = String(outputWord.reversed().prefix(while: { !$0.isLetter }).reversed())
                if trailing.hasPrefix("'") || trailing.hasPrefix("\u{2019}") { trailing.removeFirst() }
                let apostrophe = typed.tokens[i].word.contains("\u{2019}") ? "\u{2019}" : "'"
                var form = typedLetters.lowercased()
                if outputLetters.first?.isUppercase == true { form = form.prefix(1).uppercased() + form.dropFirst() }
                words[j] = leading + form + apostrophe + trailing
                continue
            }
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
