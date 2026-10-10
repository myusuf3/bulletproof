import Testing
@testable import bulletproof

struct LineBreakRestorerTests {
    private func restore(_ original: String, _ corrected: String) -> String {
        LineBreakRestorer.restore(original: original, corrected: corrected)
    }

    @Test func flattenedEmailGetsItsBlankLineBack() {
        #expect(restore("Hi Ana,\n\nThanks for teh notes.", "Hi Ana, Thanks for the notes.")
                == "Hi Ana,\n\nThanks for the notes.")
    }

    @Test func flattenedBulletsGetTheirLinesBack() {
        #expect(restore("Todo:\n- buy mlik\n- call mom", "Todo: - buy milk - call mom")
                == "Todo:\n- buy milk\n- call mom")
    }

    @Test func breakAnchorsOnTheWordBeforeWhenTheLineStartWasRewritten() {
        #expect(restore("first line\nsecnd line", "first line Second line") == "first line\nSecond line")
    }

    @Test func keptBreaksAndSingleLineTextAreUntouched() {
        #expect(restore("a\nb", "a\nb") == "a\nb")
        #expect(restore("teh cat sat", "the cat sat") == "the cat sat")
    }

    @Test func breaksTheModelAddedOrShrankAreUndone() {
        #expect(restore("one two three", "one\ntwo three") == "one two three")
        #expect(restore("Thanks.\n\nBest,\nBo", "Thanks.\nBest,\nBo") == "Thanks.\n\nBest,\nBo")
    }

    @Test func cleanResponseRestoresBreaks() {
        #expect(ProofreadPrompt.cleanResponse("Hi Bo, Do not worry.", original: "Hi Bo,\nDont worry.")
                == "Hi Bo,\nDon't worry.")
    }

    @Test func addedTrailingSpacesBeforeABreakAreRemoved() {
        #expect(restore("- buy mlik\n- call mom", "- buy milk  \n- call mom") == "- buy milk\n- call mom")
        // The writer's own trailing spaces stay.
        #expect(restore("a  \nb", "a  \nb") == "a  \nb")
    }
}
