import Foundation
import os

/// Model output is pasted destructively over the user's selection, so
/// unusable output must be caught before it reaches the pasteboard.
/// Reasons are enumerated because "model produced nothing" and "gate ate a
/// real correction" look identical once the text is gone.
nonisolated enum OutputGate {
    enum Rejection: CaseIterable, Equatable {
        case emptyOutput
        case replacementCharacter
        case introducedControlCharacters
        case introducedSymbol
        case overExpansion
        case lowOverlap
        case introducedStructure
        case droppedContent
        case droppedMarkup
        case appendedContent
        case introducedMisspelling
        case protectedWordRemoved
        case implausibleEdit
    }

    /// Ratio rules only apply above these floors - short inputs legitimately
    /// grow ("u" -> "you") and give too few words to judge overlap.
    private static let expansionMinimumCharacters = 20
    private static let overlapMinimumWords = 8

    static func rejection(original: String, output: String) -> Rejection? {
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .emptyOutput
        }
        if output.contains("\u{FFFD}") {
            return .replacementCharacter
        }
        // Only *introduced* control characters are a model glitch - the
        // user's own text may carry escape sequences or odd characters.
        let originalScalars = Set(original.unicodeScalars)
        let introducedControl = output.unicodeScalars.contains { scalar in
            scalar.properties.generalCategory == .control
                && !"\n\t\r".unicodeScalars.contains(scalar)
                && !originalScalars.contains(scalar)
        }
        if introducedControl {
            return .introducedControlCharacters
        }
        // A proofread never adds a currency sign or symbol/emoji the writer
        // didn't type: Apple Intelligence wrote "$1,299.99" as "$€1,299.99".
        let introducedSymbol = output.unicodeScalars.contains { scalar in
            [.currencySymbol, .otherSymbol].contains(scalar.properties.generalCategory)
                && !originalScalars.contains(scalar)
        }
        if introducedSymbol {
            return .introducedSymbol
        }
        if original.count >= expansionMinimumCharacters, output.count > original.count * 3 {
            return .overExpansion
        }
        // A correction keeps most of the original's words; an answer or
        // summary shares almost none of them.
        let originalWords = words(of: original)
        if originalWords.count >= overlapMinimumWords,
           originalWords.intersection(surviving(Array(originalWords), in: Array(words(of: output)))).count * 2
            < originalWords.count {
            return .lowOverlap
        }
        if introducesStructure(original: original, output: output) {
            return .introducedStructure
        }
        if dropsContent(original: original, output: output) {
            return .droppedContent
        }
        if dropsMarkup(original: original, output: output) {
            return .droppedMarkup
        }
        if appendsContent(original: original, output: output) {
            return .appendedContent
        }
        return nil
    }

    /// A correction never deletes what the writer said, but models drop
    /// sign-offs ("Kind regards,\nSofia") and whole sentences, and that paste
    /// silently loses text. Every line, and every sentence of a multi-sentence
    /// line, must survive: a sentence of 4+ words with fewer than half its
    /// words left, or (in multi-line text) a short line with none left, means
    /// content was dropped.
    /// Two or more of the writer's words deleted outright: aligned to nothing,
    /// and found nowhere else in the output (so "Me and Sam" -> "Sam and I"
    /// moves words rather than losing them; close spellings count as kept, as in
    /// lowOverlap). A repeated word ("the the") isn't
    /// content. Catches short deletions the per-sentence rule below misses
    /// ('"I dont know," she said' -> "I don't know,").
    static func deletesWords(original: String, output: String) -> Bool {
        let tokens = WordTokens(original)
        let source = tokens.keys, result = WordTokens(output).keys
        // Survival as in lowOverlap: kept verbatim or as a close spelling ("Teh" -> "The").
        let kept = surviving(original.split(whereSeparator: \.isWhitespace).map(contentKey).filter { !$0.isEmpty },
                             in: output.split(whereSeparator: \.isWhitespace).map(contentKey).filter { !$0.isEmpty })
        var lost = 0
        for case .changed(let removed, let added) in WordAlignment.steps(source, result) where added.isEmpty {
            for k in removed where !source[k].isEmpty && !(k > 0 && source[k - 1] == source[k])
                && !kept.contains(contentKey(Substring(tokens.tokens[k].word))) {
                lost += 1
            }
        }
        return lost >= 2
    }

    static func dropsContent(original: String, output: String) -> Bool {
        if deletesWords(original: original, output: output) { return true }
        // Links, emails, paths, mentions, hashtags and identifiers are never proofread, and
        // LinkRestorer has already put back respelled ones: a literal still missing was deleted
        // or rewritten (Apple Intelligence dropped a leading "<@U02ZZ9K1>").
        if LinkRestorer.links(in: original).contains(where: { !output.contains($0) }) { return true }
        let inputKeys = original.split(whereSeparator: \.isWhitespace).map(contentKey).filter { !$0.isEmpty }
        let outputKeys = output.split(whereSeparator: \.isWhitespace).map(contentKey).filter { !$0.isEmpty }
        let kept = surviving(inputKeys, in: outputKeys)
        let lines = original.split(whereSeparator: \.isNewline)
        for line in lines {
            let sentences = sentences(in: String(line))
            for sentence in sentences {
                let words = sentence.split(whereSeparator: \.isWhitespace).map(contentKey).filter { !$0.isEmpty }
                guard !words.isEmpty else { continue }
                let survivors = words.filter(kept.contains).count
                if words.count < 4 {
                    // Short whole lines (sign-offs, names) only count in
                    // multi-line text; a short single line legitimately
                    // changes completely ("u ok?" -> "Are you okay?").
                    if lines.count > 1, sentences.count == 1, survivors == 0 { return true }
                } else if survivors * 2 < words.count {
                    return true
                }
            }
        }
        return false
    }

    private static func contentKey(_ word: Substring) -> String {
        String(word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber })
    }

    /// Input words that survive into the output: kept verbatim, or *corrected*
    /// - matched one-to-one to a new output word within a small edit distance
    /// ("teh" -> "the", "bred" -> "bread"). A typo-dense sentence the model fixed
    /// is not dropped content; a translation or an answer shares neither.
    static func surviving(_ inputKeys: [String], in outputKeys: [String]) -> Set<String> {
        let inputSet = Set(inputKeys), outputSet = Set(outputKeys)
        var newWords: [String] = []
        for word in outputKeys where !inputSet.contains(word) && !newWords.contains(word) {
            newWords.append(word)
        }
        var survivors = outputSet
        var used = Set<String>()
        var seen = Set<String>()
        for word in inputKeys where !outputSet.contains(word) && seen.insert(word).inserted {
            if let match = newWords.first(where: { !used.contains($0) && isCloseSpelling(word, $0) }) {
                used.insert(match)
                survivors.insert(word)
            }
        }
        return survivors
    }

    /// Damerau-Levenshtein within 1 (words up to 4 letters) or 2 (longer); 3+ letters only.
    static func isCloseSpelling(_ a: String, _ b: String) -> Bool {
        let a = Array(a), b = Array(b)
        guard a.count >= 3, b.count >= 3 else { return false }
        let limit = min(a.count, b.count) <= 4 ? 1 : 2
        guard abs(a.count - b.count) <= limit else { return false }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count] <= limit
    }

    /// Splits after . ! ? followed by whitespace.
    private static func sentences(in line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var previous: Character?
        for character in line.trimmingCharacters(in: .whitespaces) {
            if character.isWhitespace, let p = previous, ".!?".contains(p) {
                result.append(current)
                current = ""
            } else if !(character.isWhitespace && current.isEmpty) {
                current.append(character)
            }
            previous = character
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// A correction never adds layout: new line breaks, list markers, JSON or
    /// code fences mean the model *answered* request-like text ("summarize
    /// this in bullets", "convert to JSON") - short answers like those slip
    /// past lowOverlap because they reuse the input's words.
    /// HTML/XML tags are markup, not prose: an output missing any tag the
    /// input had would paste broken markup (Apple Intelligence returns
    /// "<p>Thsi is a paragraph.</p>" as "This is a paragraph."). Tags inside
    /// backticks are already restored by CodeSpanRestorer.
    private static let markupTag = try! NSRegularExpression(
        pattern: #"</?[A-Za-z][A-Za-z0-9:-]*(?:\s+[A-Za-z_:][\w:.-]*(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*\s*/?>"#)

    /// The output is the writer's whole text and then more: the model kept
    /// generating after its echo (a 300-emoji run came back 2.3x long, under
    /// overExpansion's 3x). Punctuation-only additions ("How are you?") and a
    /// completed cut-off word ("tomorr" -> "tomorrow") don't count.
    static func appendsContent(original: String, output: String) -> Bool {
        let typed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = typed.unicodeScalars.last, result.unicodeScalars.count > typed.unicodeScalars.count,
              result.unicodeScalars.starts(with: typed.unicodeScalars) else { return false }
        let extra = result.unicodeScalars.dropFirst(typed.unicodeScalars.count)
        // Letters, numbers and marks (Thai and Indic vowel signs) are word characters.
        let wordScalar = { (scalar: Unicode.Scalar) in scalar.properties.generalCategory.isWordCharacter }
        if let first = extra.first, wordScalar(last), wordScalar(first) { return false }
        return extra.filter { !$0.properties.isWhitespace && !$0.properties.generalCategory.isPunctuation }.count >= 3
    }

    static func dropsMarkup(original: String, output: String) -> Bool {
        let tags = { (text: String) -> [String: Int] in
            let ns = text as NSString
            return markupTag.matches(in: text, range: NSRange(location: 0, length: ns.length))
                .reduce(into: [:]) { counts, match in counts[ns.substring(with: match.range), default: 0] += 1 }
        }
        let needed = tags(original)
        guard !needed.isEmpty else { return false }
        let present = tags(output)
        return needed.contains { tag, count in present[tag, default: 0] < count }
    }

    static func introducesStructure(original: String, output: String) -> Bool {
        let lineBreaks = { (text: String) in
            text.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNewline).count
        }
        if lineBreaks(output) > lineBreaks(original) { return true }
        for marker in ["{", "}", "[", "]", "```"] where output.contains(marker) && !original.contains(marker) {
            return true
        }
        let lineStarts = { (text: String) -> Set<String> in
            Set(text.split(whereSeparator: \.isNewline).compactMap { line in
                let trimmed = line.drop(while: \.isWhitespace)
                if let first = trimmed.first, "-*•#".contains(first) { return String(first) }
                if trimmed.prefix(while: \.isNumber).count > 0,
                   trimmed.drop(while: \.isNumber).hasPrefix(". ") { return "1." }
                return nil
            })
        }
        return !lineStarts(output).subtracting(lineStarts(original)).isEmpty
    }

    /// Case-preserved words the output contains that the original didn't -
    /// the candidates for the spell-check gate. Whole alphabetic words of 3+
    /// letters only: numbers and fragments have no spelling to check.
    /// Contractions stay whole - splitting "shouldn't" would hand the spell
    /// checker the non-word fragment "shouldn" and reject a real correction.
    static func introducedWords(original: String, output: String) -> [String] {
        let originalWords = Set(wordTokens(in: original).map { $0.lowercased() })
        var seen = Set<String>()
        return wordTokens(in: output).filter { word in
            let bare = word.filter { !"''".contains($0) }
            let key = word.lowercased()
            guard bare.count >= 3, bare.allSatisfy(\.isLetter),
                  !originalWords.contains(key), !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    /// Shared word tokenizer: contractions stay whole, edge apostrophes
    /// stripped. Also used by the vocabulary and the protected-word rule.
    static func wordTokens(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && !"''".contains($0) })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "''")) }
            .filter { !$0.isEmpty }
    }

    private static func words(of text: String) -> Set<String> {
        Set(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init))
    }
}

/// Wraps any engine so every consumer - hotkey, services, Shortcuts - gets
/// the same output validation, surfaced through the normal error path.
nonisolated struct OutputGatedEngine: ProofreadingEngine {
    let wrapped: any ProofreadingEngine
    /// Nil resolves to the shared vocabulary at call time - a test seam.
    private let vocabularyOverride: PersonalVocabulary?
    private static let logger = Logger(subsystem: "com.mahdiyusuf.bulletproof", category: "output-gate")

    init(wrapped: any ProofreadingEngine, vocabulary: PersonalVocabulary? = nil) {
        self.wrapped = wrapped
        self.vocabularyOverride = vocabulary
    }

    func proofread(_ text: String) async throws -> String {
        let vocabulary = await MainActor.run { [vocabularyOverride] in
            (vocabularyOverride ?? PersonalVocabulary.shared).words
        }
        let output = try await wrapped.proofread(text)
        if let rejection = OutputGate.rejection(original: text, output: output) {
            Self.logger.warning("rejected model output: \(String(describing: rejection), privacy: .public)")
            throw ProofreadingError.unusableOutput(rejection)
        }
        // A vocabulary word present in the input but gone from the output
        // means the model rewrote away something the user types on purpose
        // ("Jon" -> "John") - deterministic, no scoring needed.
        // Exception: a lowercase protected word replaced by one of the spell
        // checker's guesses was a typo the vocabulary learned after the model
        // missed it twice ("signficantly" -> "significantly") - accept the fix
        // and forget the entry. Capitalized words (names) stay fully protected:
        // their guesses include exactly the swaps to block (Caitlin -> Caitlyn).
        let outputWords = Set(OutputGate.wordTokens(in: output).map { $0.lowercased() })
        let inputTokens = OutputGate.wordTokens(in: text)
        var learnedTypos: [String] = []
        for word in inputTokens {
            let key = word.lowercased()
            guard vocabulary.contains(key), !outputWords.contains(key) else { continue }
            let alwaysLowercase = !inputTokens.contains { $0.lowercased() == key && $0 != key }
            let guesses = alwaysLowercase ? await MainActor.run { SpellCheckGate.guesses(for: word) } : []
            let fixedToGuess = guesses.contains { guess in
                let parts = OutputGate.wordTokens(in: guess).map { $0.lowercased() }
                return !parts.isEmpty && parts.allSatisfy(outputWords.contains)
            }
            guard fixedToGuess else {
                Self.logger.warning("rejected model output: removed protected word \(word, privacy: .private)")
                throw ProofreadingError.unusableOutput(.protectedWordRemoved)
            }
            learnedTypos.append(word)
        }
        let introduced = OutputGate.introducedWords(original: text, output: output)
            .filter { !vocabulary.contains($0.lowercased()) }
        let dictionary = await MainActor.run { SpellCheckGate.dictionary(forText: output) }
        if let misspelled = await SpellCheckGate.firstMisspelled(in: introduced, language: dictionary) {
            Self.logger.warning("rejected model output: introduced misspelling \(misspelled, privacy: .private)")
            throw ProofreadingError.unusableOutput(.introducedMisspelling)
        }
        // Learn only from fully accepted proofreads, and only words the
        // correction kept - never the typos it fixed.
        await MainActor.run { [vocabularyOverride, learnedTypos] in
            let vocabulary = vocabularyOverride ?? PersonalVocabulary.shared
            learnedTypos.forEach(vocabulary.forget)
            vocabulary.observe(input: text, keptIn: output)
        }
        return output
    }

    func prewarm() async {
        await wrapped.prewarm()
    }
}

private extension Unicode.GeneralCategory {
    nonisolated var isWordCharacter: Bool {
        switch self {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber, .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }

    nonisolated var isPunctuation: Bool {
        switch self {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation: true
        default: false
        }
    }
}
