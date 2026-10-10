import Testing
@testable import bulletproof

struct SpellingVariantRestorerTests {
    @Test func britishSpellingsComeBack() {
        #expect(SpellingVariantRestorer.restore(original: "I love the colour of the new kitchen.",
                                                corrected: "I love the color of the new kitchen.")
                == "I love the colour of the new kitchen.")
        #expect(SpellingVariantRestorer.restore(original: "her favourite flavour, we organised it",
                                                corrected: "Her favorite flavor, we organized it.")
                == "Her favourite flavour, we organised it.")
        #expect(SpellingVariantRestorer.restore(original: "she travelled; the centre", corrected: "She traveled; the center")
                == "She travelled; the centre")
    }

    @Test func realFixesAndAmericanWritersAreLeftAlone() {
        // Not in the table: a typo or a different word stays corrected.
        #expect(SpellingVariantRestorer.restore(original: "four the team", corrected: "for the team") == "for the team")
        #expect(SpellingVariantRestorer.restore(original: "the expence report", corrected: "the expense report") == "the expense report")
        #expect(SpellingVariantRestorer.restore(original: "I love the color", corrected: "I love the color.") == "I love the color.")
    }
}
