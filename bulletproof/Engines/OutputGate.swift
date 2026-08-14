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
        case overExpansion
        case lowOverlap
        case introducedMisspelling
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
        if original.count >= expansionMinimumCharacters, output.count > original.count * 3 {
            return .overExpansion
        }
        // A correction keeps most of the original's words; an answer or
        // summary shares almost none of them.
        let originalWords = words(of: original)
        if originalWords.count >= overlapMinimumWords,
           originalWords.intersection(words(of: output)).count * 2 < originalWords.count {
            return .lowOverlap
        }
        return nil
    }

    /// Case-preserved words the output contains that the original didn't -
    /// the candidates for the spell-check gate. Whole alphabetic words of 3+
    /// letters only: numbers and fragments have no spelling to check.
    /// Contractions stay whole - splitting "shouldn't" would hand the spell
    /// checker the non-word fragment "shouldn" and reject a real correction.
    static func introducedWords(original: String, output: String) -> [String] {
        let originalWords = Set(contractionTokens(of: original).map { $0.lowercased() })
        var seen = Set<String>()
        return contractionTokens(of: output).filter { word in
            let bare = word.filter { !"''".contains($0) }
            let key = word.lowercased()
            guard bare.count >= 3, bare.allSatisfy(\.isLetter),
                  !originalWords.contains(key), !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func contractionTokens(of text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && !"''".contains($0) })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "''")) }
            .filter { !$0.isEmpty }
    }

    private static func words(of text: String) -> Set<String> {
        Set(text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init))
    }
}

/// Wraps any engine so every consumer - hotkey, services, Shortcuts - gets
/// the same output validation, surfaced through the normal error path.
nonisolated struct OutputGatedEngine: ProofreadingEngine {
    let wrapped: any ProofreadingEngine
    private static let logger = Logger(subsystem: "com.mahdiyusuf.bulletproof", category: "output-gate")

    func proofread(_ text: String) async throws -> String {
        let output = try await wrapped.proofread(text)
        if let rejection = OutputGate.rejection(original: text, output: output) {
            Self.logger.warning("rejected model output: \(String(describing: rejection), privacy: .public)")
            throw ProofreadingError.unusableOutput(rejection)
        }
        if let misspelled = await SpellCheckGate.firstMisspelled(
                in: OutputGate.introducedWords(original: text, output: output)) {
            Self.logger.warning("rejected model output: introduced misspelling \(misspelled, privacy: .private)")
            throw ProofreadingError.unusableOutput(.introducedMisspelling)
        }
        return output
    }

    func prewarm() async {
        await wrapped.prewarm()
    }
}
