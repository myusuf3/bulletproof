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

    static func restore(original: String, corrected: String) -> String {
        var text = restoreTimes(original: original, corrected: corrected)
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
