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
        // More breaks than the original is not this restorer's business.
        #expect(restore("one two", "one\ntwo") == "one\ntwo")
    }

    @Test func cleanResponseRestoresBreaks() {
        #expect(ProofreadPrompt.cleanResponse("Hi Bo, Do not worry.", original: "Hi Bo,\nDont worry.")
                == "Hi Bo,\nDon't worry.")
    }
}
