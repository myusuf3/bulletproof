import Foundation

/// URLs, email addresses, file paths, hashtags, backslash escapes, chat mentions and
/// letter-and-digit identifiers are never proofread: a
/// typo-looking domain ("exmaple.com"), folder ("Documnets") or tag ("#teh")
/// is still the one the user meant, and a "fixed" one silently points
/// somewhere else. Each input literal missing from the output is put back
/// over the output literal that replaced it (the closest-spelled new one).
nonisolated enum LinkRestorer {
    private static let pattern = try! NSRegularExpression(pattern: [
        #"https?://[^\s<>()"'`]+"#,                              // URL
        #"[\w.+-]+@[\w-]+(?:\.[\w-]+)+"#,                          // email
        // Domain without a scheme: www., a common TLD, or a path after it (exmaple.org/faq).
        #"(?<![\w@/.:-])(?:www\.[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+|[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.(?:com|org|net|io|dev|app|co|edu|gov|ai|me|ly|uk|de|ca|us|info|biz|xyz|tv)(?![A-Za-z])|[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}(?=/))(?:/[^\s<>()"'`]*)?"#,
        #"(?<![\w/:.])(?:~|\.{1,2})?/[\w.{}~-]+(?:/[\w.{}~-]*)+"#, // Unix path or route, 2+ segments
        #"\b[A-Za-z]:\\[^\s"'`]+"#,                              // Windows path
        #"(?<![\w&#])#[A-Za-z][\w-]*"#,                           // hashtag
        #"[^\s"'`]*\\[^\s"'`]+"#,                                // any token with a backslash (escapes, ¯\_(ツ)_/¯, LaTeX)
        #"<[@#!][^<>\s]+>"#,                                       // chat mention (<@U02ABC123>, <#C123>, <!here>)
        #"(?<![\w@#/.-])(?=[A-Za-z0-9_-]*\d)(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9][A-Za-z0-9_-]{5,}(?![\w-])"#, // id mixing letters and digits (a1b2c3d, uuid)
    ].joined(separator: "|"))

    static func restore(original: String, corrected: String) -> String {
        let typed = links(in: original)
        guard !typed.isEmpty else { return corrected }
        var text = corrected
        let typedTokens = Set(original.split(whereSeparator: \.isWhitespace).map(String.init))
        for link in typed where !text.contains(link) {
            var candidates = links(in: text).filter { !typed.contains($0) }
            // A dropped backslash leaves no literal behind ("¯_(ツ)_/¯"): look at the new plain tokens.
            if candidates.isEmpty, link.contains("\\") {
                candidates = text.split(whereSeparator: \.isWhitespace).map(String.init).filter { !typedTokens.contains($0) }
            }
            guard let replaced = candidates.max(by: { similarity(link, $0) < similarity(link, $1) }),
                  similarity(link, replaced) >= 0.8
                    || OutputGate.isCloseSpelling(link.lowercased(), replaced.lowercased()),
                  let range = text.range(of: replaced) else { continue }
            text.replaceSubrange(range, with: link)
        }
        return text
    }

    /// Ranges of the links in `text` (untrimmed), for fixers that must skip them.
    static func ranges(in text: String) -> [Range<String.Index>] {
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { Range($0.range, in: text) }
    }

    /// Links in order, with trailing sentence punctuation trimmed.
    static func links(in text: String) -> [String] {
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            var link = ns.substring(with: match.range)
            while let last = link.last, ".,;:!?)".contains(last) { link.removeLast() }
            return link
        }
    }

    private static func similarity(_ a: String, _ b: String) -> Double {
        SpanTriage.similarity(a.lowercased(), b.lowercased())
    }
}
