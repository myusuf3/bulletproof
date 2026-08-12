import Foundation
import Testing
@testable import bulletproof

@MainActor
struct CorrectionHistoryTests {
    private func makeHistory() -> (CorrectionHistory, UserDefaults) {
        let suite = UserDefaults(suiteName: "history-test-\(UUID().uuidString)")!
        return (CorrectionHistory(defaults: suite), suite)
    }

    @Test func recordsNewestFirst() {
        let (history, _) = makeHistory()
        history.record(original: "teh cat", corrected: "the cat")
        history.record(original: "teh dog", corrected: "the dog")
        #expect(history.entries.map(\.corrected) == ["the dog", "the cat"])
    }

    @Test func capsAtFiveEntries() {
        let (history, _) = makeHistory()
        for i in 1...7 {
            history.record(original: "in \(i)", corrected: "out \(i)")
        }
        #expect(history.entries.count == 5)
        #expect(history.entries.first?.corrected == "out 7")
        #expect(history.entries.last?.corrected == "out 3")
    }

    @Test func skipsUnchangedCorrections() {
        let (history, _) = makeHistory()
        history.record(original: "already perfect", corrected: "already perfect")
        #expect(history.entries.isEmpty)
        // The counter still credits the proofread.
        #expect(history.wordsProofread == 2)
    }

    @Test func clearEmptiesEntriesButKeepsCounter() {
        let (history, _) = makeHistory()
        history.record(original: "teh cat", corrected: "the cat")
        history.clear()
        #expect(history.entries.isEmpty)
        #expect(history.wordsProofread == 2)
    }

    @Test func counterAccumulatesAndPersists() {
        let (history, suite) = makeHistory()
        history.record(original: "teh cat", corrected: "the cat")
        history.record(original: "a b c d", corrected: "a, b, c, d")
        #expect(history.wordsProofread == 6)
        // A fresh instance on the same defaults sees the count, not the text.
        let reloaded = CorrectionHistory(defaults: suite)
        #expect(reloaded.wordsProofread == 6)
        #expect(reloaded.entries.isEmpty)
    }

    @Test func menuPreviewTruncatesLongText() {
        let long = String(repeating: "correction ", count: 20)
        let preview = CorrectionHistory.menuPreview(long)
        #expect(preview.count <= 50)
        #expect(preview.hasSuffix("…"))
    }

    @Test func menuPreviewCollapsesNewlines() {
        let preview = CorrectionHistory.menuPreview("line one\nline two")
        #expect(!preview.contains("\n"))
        #expect(preview == "line one line two")
    }
}
