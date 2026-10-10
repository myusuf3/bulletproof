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

    @Test func theWritersTimeFormatComesBack() {
        #expect(TypographyRestorer.restore(original: "Call me at +1 (555) 123-4567 after 6pm.", corrected: "Call me at +1 (555) 123-4567 after 6 pm.")
                == "Call me at +1 (555) 123-4567 after 6pm.")
        #expect(TypographyRestorer.restore(original: "Meet me at 3:30pm on 10/12.", corrected: "Meet me at 3:30 PM on 10/12.")
                == "Meet me at 3:30pm on 10/12.")
        #expect(TypographyRestorer.restore(original: "at 11 a.m. sharp", corrected: "at 11 AM sharp") == "at 11 a.m. sharp")
        // A different time is the model's change, not a respelling; untouched times stay.
        #expect(TypographyRestorer.restore(original: "at 6pm", corrected: "at 7 pm") == "at 7 pm")
        #expect(TypographyRestorer.restore(original: "from 8am to 6pm", corrected: "From 8am to 6pm.") == "From 8am to 6pm.")
    }

    @Test func theWritersUnitsComeBack() {
        #expect(TypographyRestorer.restore(original: "It weighs 5kg and the drive is 10GB.",
                                           corrected: "It weighs 5 kilograms and the drive is 10 gigabytes.")
                == "It weighs 5kg and the drive is 10GB.")
        #expect(TypographyRestorer.restore(original: "only 300 MB left", corrected: "Only 300 megabytes left.") == "Only 300 MB left.")
        // A different number, or a unit the writer didn't type, is left alone.
        #expect(TypographyRestorer.restore(original: "5kg", corrected: "6 kilograms") == "6 kilograms")
        #expect(TypographyRestorer.restore(original: "ran 5 miles", corrected: "ran 5 kilometers") == "ran 5 kilometers")
    }

    @Test func emoticonsComeBackWhole() {
        #expect(TypographyRestorer.restore(original: "i.e. we ship monday, not tuesday :P", corrected: "i.e. we ship monday, not tuesday: P")
                == "i.e. we ship monday, not tuesday :P")
        #expect(TypographyRestorer.restore(original: "ok :-) bye", corrected: "ok : -) bye") == "ok :-) bye")
        #expect(TypographyRestorer.restore(original: "see you :)", corrected: "See you :)") == "See you :)")
    }

    @Test func edgeBracketsTheWriterLeftOpenStayOpen() {
        #expect(TypographyRestorer.restore(original: "(see the attached file", corrected: "(see the attached file)") == "(see the attached file")
        #expect(TypographyRestorer.restore(original: "she said \"hi", corrected: "she said \"hi\"") == "she said \"hi")
        #expect(TypographyRestorer.restore(original: "file) for details", corrected: "(file) for details") == "file) for details")
        // Brackets the writer closed, or a model edit inside, are left alone.
        #expect(TypographyRestorer.restore(original: "(see teh file)", corrected: "(see the file)") == "(see the file)")
        #expect(TypographyRestorer.restore(original: "call (or text) me", corrected: "Call (or text) me.") == "Call (or text) me.")
        // Braces stay, so an answer rewritten as JSON is still caught by introducedStructure.
        #expect(TypographyRestorer.restore(original: "Convert this to JSON: name Alice", corrected: "{\"name\": \"Alice\"}")
                == "{\"name\": \"Alice\"}")
    }
}
