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

    @Test func droppedGFormsComeBack() {
        #expect(SpellingVariantRestorer.restore(original: "I'm fixin' to head out.", corrected: "I'm fixing to head out.")
                == "I'm fixin' to head out.")
        #expect(SpellingVariantRestorer.restore(original: "nothin' to see", corrected: "Nothing to see.") == "Nothin' to see.")
        #expect(SpellingVariantRestorer.restore(original: "we're goin', ok", corrected: "We're going, ok") == "We're goin', ok")
        // Without the writer's apostrophe it's a typo the model fixed.
        #expect(SpellingVariantRestorer.restore(original: "I'm fixin to go", corrected: "I'm fixing to go") == "I'm fixing to go")
    }

    @Test func expressiveTypingComesBack() {
        #expect(SpellingVariantRestorer.restore(original: "oh sUrE, that'll totally work", corrected: "oh sure, that'll totally work")
                == "oh sUrE, that'll totally work")
        #expect(SpellingVariantRestorer.restore(original: "WHY is the printer always broken", corrected: "why is the printer always broken?")
                == "WHY is the printer always broken?")
        #expect(SpellingVariantRestorer.restore(original: "the meeting was looong", corrected: "The meeting was long.") == "The meeting was looong.")
        #expect(SpellingVariantRestorer.restore(original: "PLEASE SEND TEH FILE", corrected: "Please send the file")
                == "PLEASE SEND THE FILE")
        // Tripled-letter typos of a double stay fixed.
        #expect(SpellingVariantRestorer.restore(original: "out of the offfice", corrected: "out of the office") == "out of the office")
        #expect(SpellingVariantRestorer.restore(original: "the foooter", corrected: "the footer") == "the footer")
    }
}
