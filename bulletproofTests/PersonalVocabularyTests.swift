import Foundation
import Testing
@testable import bulletproof

@MainActor
struct PersonalVocabularyTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "vocab-test-\(UUID().uuidString)")!
    }

    /// Treats every word as unknown so promotion logic is tested in isolation.
    private func vocabulary(defaults: UserDefaults,
                            unknown: @escaping (String) -> Bool = { _ in true }) -> PersonalVocabulary {
        PersonalVocabulary(defaults: defaults, isUnknownWord: unknown)
    }

    @Test func unknownWordIsLearnedOnSecondSighting() {
        let vocab = vocabulary(defaults: freshDefaults())
        vocab.observe("ping Priya about the launch")
        #expect(!vocab.contains("Priya"))
        vocab.observe("Priya says hi")
        #expect(vocab.contains("Priya"))
    }

    @Test func repeatsWithinOneObservationCountOnce() {
        // "Priya Priya Priya" in one paste is one sighting, not three.
        let vocab = vocabulary(defaults: freshDefaults())
        vocab.observe("Priya Priya Priya")
        #expect(!vocab.contains("Priya"))
    }

    @Test func dictionaryWordsAreNeverLearned() {
        let vocab = vocabulary(defaults: freshDefaults(), unknown: { $0.lowercased() == "kanban" })
        vocab.observe("move the kanban card today")
        vocab.observe("the kanban card moved today")
        #expect(vocab.contains("kanban"))
        #expect(!vocab.contains("card"))
        #expect(!vocab.contains("today"))
    }

    @Test func matchingIsCaseInsensitive() {
        let vocab = vocabulary(defaults: freshDefaults())
        vocab.observe("the KANBAN board")
        vocab.observe("a kanban column")
        #expect(vocab.contains("Kanban"))
        #expect(vocab.contains("kanban"))
    }

    @Test func learnedWordsSurviveRelaunch() {
        let defaults = freshDefaults()
        let first = vocabulary(defaults: defaults)
        first.observe("ask Priya")
        first.observe("tell Priya")
        #expect(vocabulary(defaults: defaults).contains("Priya"))
    }

    @Test func shortAndNumericTokensAreIgnored() {
        let vocab = vocabulary(defaults: freshDefaults())
        vocab.observe("at 3pm we go")
        vocab.observe("at 3pm we go")
        #expect(!vocab.contains("3pm"))
        #expect(!vocab.contains("at"))
        #expect(!vocab.contains("we"))
    }

    @Test func contractionsStayWhole() {
        let vocab = vocabulary(defaults: freshDefaults())
        vocab.observe("y'all should come")
        vocab.observe("y'all were right")
        #expect(vocab.contains("y'all"))
    }

    @Test func vocabularyIsCapped() {
        let vocab = vocabulary(defaults: freshDefaults())
        for round in 0..<2 {
            _ = round
            let words = (0..<600).map { "zzworda\($0)qq" }.joined(separator: " ")
            vocab.observe(words)
        }
        #expect(vocab.words.count <= 500)
    }
}

struct VocabularyGateIntegrationTests {
    @Test func learnedWordIsNotFlaggedAsIntroducedMisspelling() async throws {
        // The model corrects "kanbn" to "Kanban": an introduced word the
        // spell checker flags - only the personal vocabulary can save it.
        let defaults = UserDefaults(suiteName: "vocab-gate-\(UUID().uuidString)")!
        let vocab = await MainActor.run {
            PersonalVocabulary(defaults: defaults, isUnknownWord: { _ in true })
        }
        await MainActor.run {
            vocab.observe("the Kanban board")
            vocab.observe("a Kanban column")
        }
        let engine = OutputGatedEngine(wrapped: CannedGateEngine(output: "move the Kanban card"),
                                       vocabulary: vocab)
        #expect(try await engine.proofread("move the kanbn card") == "move the Kanban card")
    }

    @Test func unknownIntroducedGibberishIsStillRejected() async {
        let defaults = UserDefaults(suiteName: "vocab-gate-\(UUID().uuidString)")!
        let vocab = await MainActor.run {
            PersonalVocabulary(defaults: defaults, isUnknownWord: { _ in true })
        }
        let engine = OutputGatedEngine(wrapped: CannedGateEngine(output: "the xqzzrtl cat"),
                                       vocabulary: vocab)
        do {
            _ = try await engine.proofread("teh cat")
            Issue.record("expected unusableOutput")
        } catch let error as ProofreadingError {
            guard case .unusableOutput(.introducedMisspelling) = error else {
                Issue.record("expected introducedMisspelling, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}

private struct CannedGateEngine: ProofreadingEngine {
    var output: String
    func proofread(_ text: String) async throws -> String { output }
}
