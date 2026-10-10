import Testing
@testable import bulletproof

struct TypographyRestorerTests {
    @Test func smartPunctuationComesBack() {
        #expect(TypographyRestorer.restore(original: "She said \u{201C}we\u{2019}ll see\u{201D} and left erly.",
                                           corrected: "She said \"we\u{2019}ll see\" and left early.")
                == "She said \u{201C}we\u{2019}ll see\u{201D} and left early.")
        #expect(TypographyRestorer.restore(original: "in 5 min \u{2014} maybe 10", corrected: "in 5 minutes -- maybe 10")
                == "in 5 minutes \u{2014} maybe 10")
        #expect(TypographyRestorer.restore(original: "a \u{2014} b", corrected: "a --- b") == "a \u{2014} b")
        #expect(TypographyRestorer.restore(original: "We\u{2019}ve got it\u{2026} mostly.", corrected: "We\u{2019}ve got it... mostly.")
                == "We\u{2019}ve got it\u{2026} mostly.")
    }

    @Test func asciiWritersAndCodeAreLeftAlone() {
        #expect(TypographyRestorer.restore(original: "she said \"hi\" -- ok...", corrected: "She said \"hi\" -- ok...")
                == "She said \"hi\" -- ok...")
        #expect(TypographyRestorer.restore(original: "run it \u{2014} see \u{201C}docs\u{201D}",
                                           corrected: "run `a -- b` -- see \"docs\"")
                == "run `a -- b` \u{2014} see \u{201C}docs\u{201D}")
    }
}
