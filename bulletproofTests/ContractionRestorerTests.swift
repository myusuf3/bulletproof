import Testing
@testable import bulletproof

struct ContractionRestorerTests {
    private func restore(_ original: String, _ corrected: String) -> String {
        ContractionRestorer.restore(original: original, corrected: corrected)
    }

    @Test func expandedMissingApostropheContractionIsRecontracted() {
        #expect(restore("the cache wasnt cleared", "the cache was not cleared") == "the cache wasn't cleared")
        #expect(restore("Its recommended in CI.", "It is recommended in CI.") == "It's recommended in CI.")
        #expect(restore("we cant ship", "we cannot ship") == "we can't ship")
    }

    @Test func casingAndPunctuationFollowTheCorrection() {
        #expect(restore("im late, sorry", "I am late, sorry") == "I'm late, sorry")
        #expect(restore("ok, its fine", "ok, it is, fine") == "ok, it's, fine")
        #expect(restore("it isnt— ok", "it is not— ok") == "it isn't— ok")
    }

    @Test func expansionsTheWriterTypedAreLeftAlone() {
        #expect(restore("I do not agree", "I do not agree") == "I do not agree")
        #expect(restore("It is fine and its done", "It is fine and it's done") == "It is fine and it's done")
    }

    @Test func otherReplacementsAreLeftAlone() {
        // "its" -> "their" is a word change, not an expansion.
        #expect(restore("its going well", "their going well") == "their going well")
        // Two typed words never collapse into one contraction.
        #expect(restore("do no go", "do not go") == "do not go")
    }

    @Test func lineBreaksAndEdgeWhitespaceSurvive() {
        let original = "  Summary:\n- it wasnt cached\n- Its fine \n"
        let corrected = "  Summary:\n- it was not cached\n- It is fine \n"
        #expect(restore(original, corrected) == "  Summary:\n- it wasn't cached\n- It's fine \n")
    }

    @Test func cleanResponseRestoresContractions() {
        #expect(ProofreadPrompt.cleanResponse("I do not know", original: "i dont know") == "I don't know")
    }
}
