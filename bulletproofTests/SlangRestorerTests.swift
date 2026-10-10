import Testing
@testable import bulletproof

struct SlangRestorerTests {
    private func restore(_ original: String, _ corrected: String) -> String {
        SlangRestorer.restore(original: original, corrected: corrected)
    }

    @Test func expandedAbbreviationsComeBack() {
        #expect(restore("red on lint bc of a typo", "red on lint because of a typo") == "red on lint bc of a typo")
        #expect(restore("tbh its fine", "To be honest, it's fine") == "tbh, it's fine")
        #expect(restore("thx for the help", "Thanks for the help") == "thx for the help")
        #expect(restore("idk if it werks", "I don't know if it works") == "idk if it works")
        // Punctuation attached to the typed abbreviation.
        #expect(restore("happy bday!! hope its fun", "happy birthday!! hope it's fun") == "happy bday!! hope it's fun")
        #expect(restore("thx, see you", "Thanks, see you") == "thx, see you")
    }

    @Test func otherEditsAndRealWordsAreLeftAlone() {
        // "u" -> "your" isn't an expansion of "u".
        #expect(restore("is u car here", "is your car here") == "is your car here")
        // Expansions the writer typed are untouched.
        #expect(restore("because of rain", "because of rain") == "because of rain")
        #expect(restore("teh cat", "the cat") == "the cat")
    }

    @Test func adjacentAbbreviationsComeBackTogether() {
        #expect(SlangRestorer.restore(original: "sounds good 👍🏽 see u tmrw", corrected: "sounds good 👍🏽 see you tomorrow")
                == "sounds good 👍🏽 see u tmrw")
        #expect(SlangRestorer.restore(original: "bc u said so", corrected: "because you said so") == "bc u said so")
        // A non-abbreviation in the run keeps its correction.
        #expect(SlangRestorer.restore(original: "im omw rn", corrected: "I'm on my way right now") == "I'm omw rn")
    }

    @Test func unitAndChatAbbreviationsComeBack() {
        #expect(SlangRestorer.restore(original: "I\u{2019}ll be there in 5 min \u{2014} maybe 10.",
                                      corrected: "I\u{2019}ll be there in 5 minutes \u{2014} maybe 10.")
                == "I\u{2019}ll be there in 5 min \u{2014} maybe 10.")
        #expect(SlangRestorer.restore(original: "ppl r here tho", corrected: "people r here though") == "ppl r here tho")
        // Only the listed expansion counts: "min" corrected to "mine" stays corrected.
        #expect(SlangRestorer.restore(original: "that one is min", corrected: "that one is mine") == "that one is mine")
    }

    @Test func weekdayAndMonthAbbreviationsComeBack() {
        #expect(SlangRestorer.restore(original: "fyi the vet appt moved to thurs at 4", corrected: "fyi, the vet appt moved to Thursday at 4")
                == "fyi, the vet appt moved to thurs at 4")
        #expect(SlangRestorer.restore(original: "due sept 3", corrected: "due September 3") == "due sept 3")
        // "sun" the star is never rewritten as Sunday, so nothing to undo.
        #expect(SlangRestorer.restore(original: "the sun is out", corrected: "The sun is out.") == "The sun is out.")
    }
}
