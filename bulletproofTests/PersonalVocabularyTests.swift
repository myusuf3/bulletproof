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
        vocab.observe(input: "ping Priya about the launch", keptIn: "ping Priya about the launch")
        #expect(!vocab.contains("Priya"))
        vocab.observe(input: "Priya says hi", keptIn: "Priya says hi")
        #expect(vocab.contains("Priya"))
    }

    @Test func repeatsWithinOneObservationCountOnce() {
        // "Priya Priya Priya" in one paste is one sighting, not three.
        let vocab = vocabulary(defaults: freshDefaults())
        vocab.observe(input: "Priya Priya Priya", keptIn: "Priya Priya Priya")
        #expect(!vocab.contains("Priya"))
    }

    @Test func dictionaryWordsAreNeverLearned() {
        let vocab = vocabulary(defaults: freshDefaults(), unknown: { $0.lowercased() == "kanban" })
        vocab.observe(input: "move the kanban card today", keptIn: "move the kanban card today")
        vocab.observe(input: "the kanban card moved today", keptIn: "the kanban card moved today")
        #expect(vocab.contains("kanban"))
        #expect(!vocab.contains("card"))
        #expect(!vocab.contains("today"))
    }

    @Test func matchingIsCaseInsensitive() {
        let vocab = vocabulary(defaults: freshDefaults())
        vocab.observe(input: "the KANBAN board", keptIn: "the KANBAN board")
        vocab.observe(input: "a kanban column", keptIn: "a kanban column")
        #expect(vocab.contains("Kanban"))
        #expect(vocab.contains("kanban"))
    }

    @Test func learnedWordsSurviveRelaunch() {
        let defaults = freshDefaults()
        let first = vocabulary(defaults: defaults)
        first.observe(input: "ask Priya", keptIn: "ask Priya")
        first.observe(input: "tell Priya", keptIn: "tell Priya")
        #expect(vocabulary(defaults: defaults).contains("Priya"))
    }

    @Test func shortAndNumericTokensAreIgnored() {
        let vocab = vocabulary(defaults: freshDefaults())
        vocab.observe(input: "at 3pm we go", keptIn: "at 3pm we go")
        vocab.observe(input: "at 3pm we go", keptIn: "at 3pm we go")
        #expect(!vocab.contains("3pm"))
        #expect(!vocab.contains("at"))
        #expect(!vocab.contains("we"))
    }

    @Test func contractionsStayWhole() {
        let vocab = vocabulary(defaults: freshDefaults())
        vocab.observe(input: "y'all should come", keptIn: "y'all should come")
        vocab.observe(input: "y'all were right", keptIn: "y'all were right")
        #expect(vocab.contains("y'all"))
    }

    @Test func wordsCorrectedAwayAreNeverLearned() {
        // The self-poisoning bug CI caught: learning "teh" from inputs would
        // protect the typo and block its own correction forever.
        let vocab = vocabulary(defaults: freshDefaults())
        vocab.observe(input: "teh cat", keptIn: "the cat")
        vocab.observe(input: "teh dog", keptIn: "the dog")
        #expect(!vocab.contains("teh"))
    }

    @Test func vocabularyIsCapped() {
        let vocab = vocabulary(defaults: freshDefaults())
        for round in 0..<2 {
            _ = round
            let words = (0..<600).map { "zzworda\($0)qq" }.joined(separator: " ")
            vocab.observe(input: words, keptIn: words)
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
            vocab.observe(input: "the Kanban board", keptIn: "the Kanban board")
            vocab.observe(input: "a Kanban column", keptIn: "a Kanban column")
        }
        let engine = OutputGatedEngine(wrapped: CannedGateEngine(output: "move the Kanban card"),
                                       vocabulary: vocab)
        #expect(try await engine.proofread("move the kanbn card") == "move the Kanban card")
    }

    @Test func removingAProtectedWordIsRejected() async {
        // The "Jon -> John" class, caught deterministically: the model
        // rewrote away a word the user demonstrably types on purpose.
        let defaults = UserDefaults(suiteName: "vocab-gate-\(UUID().uuidString)")!
        let vocab = await MainActor.run {
            PersonalVocabulary(defaults: defaults, isUnknownWord: { _ in true })
        }
        await MainActor.run {
            vocab.observe(input: "ping Jon today", keptIn: "ping Jon today")
            vocab.observe(input: "Jon is out", keptIn: "Jon is out")
        }
        let engine = OutputGatedEngine(wrapped: CannedGateEngine(output: "We hired John yesterday."),
                                       vocabulary: vocab)
        do {
            _ = try await engine.proofread("We hired Jon yesterday.")
            Issue.record("expected unusableOutput")
        } catch let error as ProofreadingError {
            guard case .unusableOutput(.protectedWordRemoved) = error else {
                Issue.record("expected protectedWordRemoved, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func keepingAProtectedWordPassesEvenWhenCaseChanges() async throws {
        let defaults = UserDefaults(suiteName: "vocab-gate-\(UUID().uuidString)")!
        let vocab = await MainActor.run {
            PersonalVocabulary(defaults: defaults, isUnknownWord: { _ in true })
        }
        await MainActor.run {
            vocab.observe(input: "the kanban board", keptIn: "the kanban board")
            vocab.observe(input: "a kanban column", keptIn: "a kanban column")
        }
        let engine = OutputGatedEngine(wrapped: CannedGateEngine(output: "Move the Kanban card."),
                                       vocabulary: vocab)
        #expect(try await engine.proofread("move the kanban card") == "Move the Kanban card.")
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
