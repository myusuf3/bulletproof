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
}
