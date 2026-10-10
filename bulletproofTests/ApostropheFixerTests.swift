import Testing
@testable import bulletproof

struct ApostropheFixerTests {
    @Test func unambiguousMissingApostrophesAreFixed() {
        #expect(ApostropheFixer.fix("Im late and I dont know why it wasnt saved") == "I'm late and I don't know why it wasn't saved")
        #expect(ApostropheFixer.fix("Ive attached it, thats all.") == "I've attached it, that's all.")
        #expect(ApostropheFixer.fix("DONT panic") == "DON'T panic")
    }

    @Test func realWordsAndExistingApostrophesAreLeftAlone() {
        #expect(ApostropheFixer.fix("we cant say it well, its won't") == "we cant say it well, its won't")
        #expect(ApostropheFixer.fix("I don't think so") == "I don't think so")
    }

    @Test func codeAndIdentifiersAreLeftAlone() {
        #expect(ApostropheFixer.fix("set `dont` and dont_cache and #dont") == "set `dont` and dont_cache and #dont")
    }

    @Test func cleanResponseFixesThemAndKeepsLowercase() {
        #expect(ProofreadPrompt.cleanResponse("im on my way", original: "im on my way", keepsLowercase: true)
                == "i'm on my way")
    }
}
