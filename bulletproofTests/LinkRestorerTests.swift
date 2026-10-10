import Testing
@testable import bulletproof

struct LinkRestorerTests {
    @Test func linksAreNeverProofread() {
        #expect(LinkRestorer.restore(original: "the url is https://exmaple.com/a_b?c=d btw",
                                     corrected: "the url is https://example.com/a_b?c=d btw")
                == "the url is https://exmaple.com/a_b?c=d btw")
        #expect(LinkRestorer.restore(original: "email bo@exmaple.com for acess",
                                     corrected: "email bo@example.com for access")
                == "email bo@exmaple.com for access")
    }

    @Test func untouchedOrUnrelatedLinksAreLeftAlone() {
        #expect(LinkRestorer.restore(original: "see https://a.com.", corrected: "See https://a.com.")
                == "See https://a.com.")
        // A different link isn't a respelling of the original.
        #expect(LinkRestorer.restore(original: "go to https://a.com", corrected: "go to https://totally-other.org")
                == "go to https://totally-other.org")
        #expect(LinkRestorer.restore(original: "no links here", corrected: "No links here.") == "No links here.")
    }

    @Test func pathsAndHashtagsAreNeverProofread() {
        #expect(LinkRestorer.restore(original: #"copy it to C:\Users\bo\Documnets\backup first"#,
                                     corrected: #"copy it to C:\Users\bo\Documents\backup first"#)
                == #"copy it to C:\Users\bo\Documnets\backup first"#)
        #expect(LinkRestorer.restore(original: "posting it with #teh lol", corrected: "posting it with #the lol")
                == "posting it with #teh lol")
        #expect(LinkRestorer.restore(original: "GET /v3/users/{id}/prefernces.",
                                     corrected: "GET /v3/users/{id}/preferences.")
                == "GET /v3/users/{id}/prefernces.")
        // Not literals: dates, and/or, single-segment slash commands, headings.
        #expect(LinkRestorer.links(in: "on 10/12, and/or /remind me\n# Notes").isEmpty)
    }

    @Test func backslashEscapesAreNeverProofread() {
        #expect(LinkRestorer.restore(original: "\u{AF}\\_(\u{30C4})_/\u{AF} idk", corrected: "\u{AF}_(\u{30C4})_/\u{AF} idk")
                == "\u{AF}\\_(\u{30C4})_/\u{AF} idk")
        #expect(LinkRestorer.restore(original: "use \\alpha and \\beta", corrected: "Use \\alpha and \\beta.") == "Use \\alpha and \\beta.")
    }
}
