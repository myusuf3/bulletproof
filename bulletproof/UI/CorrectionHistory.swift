import Foundation
import Observation

/// Recent corrections for the menu bar, newest first, capped at five.
/// Entries are memory-only by design - proofread content is the user's own
/// text and never touches disk. Only the aggregate word counter persists.
@MainActor @Observable
final class CorrectionHistory {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let original: String
        let corrected: String
        let date: Date
    }

    private static let maxEntries = 5
    private static let counterKey = "wordsProofread"

    private(set) var entries: [Entry] = []
    private(set) var wordsProofread: Int

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.wordsProofread = defaults.integer(forKey: Self.counterKey)
    }

    func record(original: String, corrected: String) {
        wordsProofread += corrected.split(whereSeparator: \.isWhitespace).count
        defaults.set(wordsProofread, forKey: Self.counterKey)
        // An unchanged result is a successful proofread but a useless entry.
        guard corrected != original else { return }
        entries.insert(Entry(original: original, corrected: corrected, date: Date()), at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }

    /// Single-line snippet fit for a menu item title.
    nonisolated static func menuPreview(_ text: String, limit: Int = 48) -> String {
        let oneLine = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard oneLine.count > limit else { return oneLine }
        return oneLine.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Wraps any engine so every successful proofread - hotkey, services,
/// Shortcuts, onboarding practice - lands in the history without per-path
/// wiring.
nonisolated struct RecordingEngine: ProofreadingEngine {
    let wrapped: any ProofreadingEngine

    func proofread(_ text: String) async throws -> String {
        let corrected = try await wrapped.proofread(text)
        await MainActor.run {
            AppState.shared.history.record(original: text, corrected: corrected)
        }
        return corrected
    }

    func prewarm() async {
        await wrapped.prewarm()
    }
}
