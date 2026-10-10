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
    }

    @Test func otherEditsAndRealWordsAreLeftAlone() {
        // "u" -> "your" isn't an expansion of "u".
        #expect(restore("is u car here", "is your car here") == "is your car here")
        // Expansions the writer typed are untouched.
        #expect(restore("because of rain", "because of rain") == "because of rain")
        #expect(restore("teh cat", "the cat") == "the cat")
    }
}
