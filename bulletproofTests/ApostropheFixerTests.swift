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

    @Test func misplacedApostrophesAreFixed() {
        #expect(ApostropheFixer.fix("the view would't load") == "the view wouldn't load")
        #expect(ApostropheFixer.fix("It does'nt work, I ca'nt tell") == "It doesn't work, I can't tell")
        #expect(ApostropheFixer.fix("WOULD'NT") == "WOULDN'T")
        #expect(ApostropheFixer.fix("it does\u{2019}t") == "it doesn\u{2019}t")
        // Real words and correct contractions stay; short stems aren't guessed.
        #expect(ApostropheFixer.fix("don't won't is't `would't`") == "don't won't is't `would't`")
    }

    @Test func runTogetherPhrasesAreSplit() {
        #expect(ApostropheFixer.fix("thanks alot, atleast it works") == "thanks a lot, at least it works")
        #expect(ApostropheFixer.fix("Alot of people") == "A lot of people")
        #expect(ApostropheFixer.fix("ALOT") == "A LOT")
        // Never inside code, links, hashtags or longer words.
        #expect(ApostropheFixer.fix("`alot` https://alot.com/dont #alot alotment")
                == "`alot` https://alot.com/dont #alot alotment")
    }
}
