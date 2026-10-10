import Foundation

/// Smart punctuation is the writer's style (macOS substitutes it by default),
/// but Apple Intelligence flattens it: “quoted” → "quoted", — → --, … → ...
/// When the original uses only the typographic form of a mark, any ASCII
/// stand-in in the output was introduced by the model, so the writer's form
/// comes back. Code spans, fences and links are never touched.
nonisolated enum TypographyRestorer {
    /// A clock time with am/pm: "6pm", "8 AM", "3:30 p.m.".
    private static let clockTime = try! NSRegularExpression(
        pattern: #"(?<![\w:])(\d{1,2}(?::\d{2})?)\s?([AaPp])\.?\s?[Mm]\.?(?![\w])"#)

    private static func clockTimes(in text: String) -> [(range: Range<String.Index>, token: String, key: String)] {
        let ns = text as NSString
        return clockTime.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let key = ns.substring(with: match.range(at: 1)) + ns.substring(with: match.range(at: 2)).lowercased()
            return (range, String(text[range]), key)
        }
    }

    /// The writer's way of writing a time ("6pm", "3:30pm") is style: when the
    /// output has the same time spelled differently ("6 pm", "3:30 PM"), the
    /// writer's spelling comes back.
    static func restoreTimes(original: String, corrected: String) -> String {
        let typed = clockTimes(in: original)
        guard !typed.isEmpty else { return corrected }
        var text = corrected
        let typedTokens = Set(typed.map(\.token))
        for time in typed where !text.contains(time.token) {
            guard let replaced = clockTimes(in: text).first(where: { $0.key == time.key && !typedTokens.contains($0.token) })
            else { continue }
            text.replaceSubrange(replaced.range, with: time.token)
        }
        return text
    }

    /// Unit symbols the writer typed after a number, with the names a model spells them out as.
    private static let unitNames: [String: [String]] = [
        "kg": ["kilogram", "kilograms", "kilos"],
        "g": ["gram", "grams"],
        "mg": ["milligram", "milligrams"],
        "lb": ["pound", "pounds"],
        "lbs": ["pounds"],
        "oz": ["ounce", "ounces"],
        "km": ["kilometer", "kilometers", "kilometre", "kilometres"],
        "cm": ["centimeter", "centimeters", "centimetre", "centimetres"],
        "mm": ["millimeter", "millimeters", "millimetre", "millimetres"],
        "mi": ["mile", "miles"],
        "ft": ["foot", "feet"],
        "ml": ["milliliter", "milliliters", "millilitre", "millilitres"],
        "gb": ["gigabyte", "gigabytes"],
        "mb": ["megabyte", "megabytes"],
        "kb": ["kilobyte", "kilobytes"],
        "tb": ["terabyte", "terabytes"],
        "ghz": ["gigahertz"],
        "mhz": ["megahertz"],
        "hz": ["hertz"],
    ]

    private static let measurement = try! NSRegularExpression(
        pattern: #"(?<![\w.,])(\d+(?:[.,]\d+)?)\s?([A-Za-z]+)(?![\w])"#)

    /// The writer's "5kg" / "10GB" is style: when the output has the same
    /// number followed by that unit's name ("5 kilograms"), the typed form
    /// comes back. Restore-only, like SlangRestorer.
    static func restoreUnits(original: String, corrected: String) -> String {
        var text = corrected
        let ns = original as NSString
        for match in measurement.matches(in: original, range: NSRange(location: 0, length: ns.length)) {
            let typed = ns.substring(with: match.range), number = ns.substring(with: match.range(at: 1))
            guard let names = unitNames[ns.substring(with: match.range(at: 2)).lowercased()], !text.contains(typed) else { continue }
            let alternatives = names.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            guard let spelled = try? NSRegularExpression(
                pattern: "(?<![\\w.,])" + NSRegularExpression.escapedPattern(for: number) + "\\s(?:" + alternatives + ")(?![\\w])",
                options: [.caseInsensitive]),
                let found = spelled.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
                let range = Range(found.range, in: text) else { continue }
            text.replaceSubrange(range, with: typed)
        }
        return text
    }

    private static let emoticon = try! NSRegularExpression(
        pattern: #"(?<!\S)(?:[:;=8][-o']?[)(\]\[DPpOo/\\|*3$]|[xX][Dd]|<3|\^_\^|:'\()(?=$|\s|[.,!?])"#)

    /// Emoticons are the writer's text, but a model can read ":P" as a colon
    /// and a letter (": P"). A typed emoticon missing from the output comes
    /// back where the output has the same characters with spaces in between.
    static func restoreEmoticons(original: String, corrected: String) -> String {
        let ns = original as NSString
        var text = corrected
        for match in emoticon.matches(in: original, range: NSRange(location: 0, length: ns.length)) {
            let typed = ns.substring(with: match.range)
            guard !text.contains(typed) else { continue }
            let spaced = typed.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s*")
            guard let pattern = try? NSRegularExpression(pattern: spaced),
                  let found = pattern.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
                  let range = Range(found.range, in: text) else { continue }
            // The writer's emoticon stood alone; keep it apart from the word the model glued it to.
            let glued = range.lowerBound > text.startIndex && !text[text.index(before: range.lowerBound)].isWhitespace
            text.replaceSubrange(range, with: (glued ? " " : "") + typed)
        }
        return text
    }

    static func restore(original: String, corrected: String) -> String {
        var text = restoreEmoticons(original: original, corrected:
            restoreUnits(original: original, corrected: restoreTimes(original: original, corrected: corrected)))
        // Em dash and ellipsis: the writer's character replaces the model's stand-in
        // (a triple hyphen first, so "---" doesn't become "—-").
        for (typographic, ascii) in [("\u{2014}", "---"), ("\u{2014}", "--"), ("\u{2026}", "...")]
        where original.contains(typographic) && !original.contains(ascii) && text.contains(ascii) {
            text = replacingUnprotected(ascii, with: typographic, in: text)
        }
        // Double quotes: curly writers get curly quotes, opening after a space, line start or bracket.
        if original.contains(where: { $0 == "\u{201C}" || $0 == "\u{201D}" }), !original.contains("\""), text.contains("\"") {
            let protected = protectedRanges(in: text)
            var result = ""
            var previous: Character?
            for index in text.indices {
                let character = text[index]
                if character == "\"", !protected.contains(where: { $0.contains(index) }) {
                    let opens = previous.map { $0.isWhitespace || "([{\u{2014}".contains($0) } ?? true
                    result.append(opens ? "\u{201C}" : "\u{201D}")
                } else {
                    result.append(character)
                }
                previous = character
            }
            text = result
        }
        return text
    }

    private static func protectedRanges(in text: String) -> [Range<String.Index>] {
        CodeSpanRestorer.spans(in: text) + CodeSpanRestorer.fences(in: text) + LinkRestorer.ranges(in: text)
    }

    private static func replacingUnprotected(_ target: String, with replacement: String, in text: String) -> String {
        let protected = protectedRanges(in: text)
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix(target), !protected.contains(where: { $0.contains(index) }) {
                result += replacement
                index = text.index(index, offsetBy: target.count)
            } else {
                result.append(text[index])
                index = text.index(after: index)
            }
        }
        return result
    }
}
