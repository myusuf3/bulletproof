import Foundation

/// Backticked code is never proofread ("keep the writer's style exactly"),
/// but models unwrap it (`userID` -> userID), swap the backticks for quotes
/// (`--dry-run` -> "--dry-run"), or edit inside it (`--output <path>` ->
/// `--output<path>`). Put each of the original's code spans back:
/// - same number of spans in the output: restore each span's content in order;
/// - otherwise, per missing span: a quoted copy gets its backticks back, else
///   the first bare whole-word copy outside code is re-wrapped.
/// A span the model rewrote beyond recognition is left alone.
nonisolated enum CodeSpanRestorer {
    static func restore(original: String, corrected: String) -> String {
        let source = spans(in: original).map { String(original[$0]) }
        guard !source.isEmpty else { return corrected }
        var text = corrected
        let output = spans(in: text)
        if output.count == source.count {
            for (range, content) in zip(output, source).reversed() where text[range] != content {
                text.replaceSubrange(range, with: content)
            }
            return text
        }
        for content in source where !text.contains("`" + content + "`") {
            let quoted = [("\"", "\""), ("'", "'"), ("\u{201C}", "\u{201D}"), ("\u{2018}", "\u{2019}")]
                .map { $0.0 + content + $0.1 }
                .first { text.contains($0) }
            if let quoted, let range = text.range(of: quoted) {
                text.replaceSubrange(range, with: "`" + content + "`")
            } else if let range = bareOccurrence(of: content, in: text) {
                text.replaceSubrange(range, with: "`" + content + "`")
            }
        }
        return text
    }

    /// Ranges of the text between single-line backtick pairs.
    static func spans(in text: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var index = text.startIndex
        while let open = text[index...].firstIndex(of: "`") {
            let start = text.index(after: open)
            guard let close = text[start...].firstIndex(where: { $0 == "`" || $0.isNewline }) else { break }
            if text[close] == "`", close > start {
                result.append(start..<close)
                index = text.index(after: close)
            } else {
                index = text[close] == "`" ? text.index(after: close) : close
            }
        }
        return result
    }

    /// First occurrence of `content` that isn't part of a longer word and
    /// isn't already inside a code span.
    private static func bareOccurrence(of content: String, in text: String) -> Range<String.Index>? {
        let code = spans(in: text)
        var searchStart = text.startIndex
        while let range = text.range(of: content, range: searchStart..<text.endIndex) {
            let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : " "
            let after = range.upperBound < text.endIndex ? text[range.upperBound] : " "
            let isWordChar = { (c: Character) in c.isLetter || c.isNumber || c == "_" || c == "`" }
            let insideCode = code.contains { $0.overlaps(range) }
            if !isWordChar(before), !isWordChar(after), !insideCode {
                return range
            }
            searchStart = text.index(after: range.lowerBound)
        }
        return nil
    }
}
