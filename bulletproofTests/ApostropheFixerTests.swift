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

    @Test func nonEnglishTextIsLeftAlone() {
        // "im" is German, "dont" French - only English text gets apostrophes.
        #expect(ProofreadPrompt.cleanResponse("Ich bin im Büro und warte auf dich.",
                                              original: "Ich bin im Büro und warte auf dich.")
                == "Ich bin im Büro und warte auf dich.")
        #expect(ProofreadPrompt.cleanResponse("Le livre dont tu parles est très bon.",
                                              original: "Le livre dont tu parles est tres bon.")
                == "Le livre dont tu parles est très bon.")
        #expect(ProofreadPrompt.cleanResponse("im on my way, dont wait", original: "im on my way, dont wait",
                                              keepsLowercase: true) == "i'm on my way, don't wait")
    }
}
