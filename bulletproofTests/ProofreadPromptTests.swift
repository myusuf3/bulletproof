import Testing
@testable import bulletproof

struct ProofreadPromptTests {
    @Test func restoresLeadingAndTrailingSpaces() {
        let result = ProofreadPrompt.restoreEdgeWhitespace(of: "  teh cat ", onto: "the cat")
        #expect(result == "  the cat ")
    }

    @Test func restoresNewlines() {
        let result = ProofreadPrompt.restoreEdgeWhitespace(of: "\nteh cat\n\n", onto: "the cat")
        #expect(result == "\nthe cat\n\n")
    }

    @Test func stripsWhitespaceTheModelAdded() {
        let result = ProofreadPrompt.restoreEdgeWhitespace(of: "teh cat", onto: "the cat\n")
        #expect(result == "the cat")
    }

    @Test func unchangedTextPassesThrough() {
        let result = ProofreadPrompt.restoreEdgeWhitespace(of: "the cat", onto: "the cat")
        #expect(result == "the cat")
    }

    @Test func interiorWhitespaceIsPreserved() {
        let result = ProofreadPrompt.restoreEdgeWhitespace(of: " a\nb ", onto: "a\nb")
        #expect(result == " a\nb ")
    }

    @Test func userPromptWrapsTextInMarkers() {
        #expect(ProofreadPrompt.userPrompt(for: "hi") == "<text>\nhi\n</text>")
    }

    @Test func cleanResponseStripsLeakedMarkers() {
        let result = ProofreadPrompt.cleanResponse("<text>\nthe cat\n</text>", original: "teh cat")
        #expect(result == "the cat")
    }

    @Test func cleanResponseKeepsTheWritersOwnEdgeMarkers() {
        // SVG/XML: the writer's text itself ends (or starts) with the marker.
        #expect(ProofreadPrompt.cleanResponse(#"<text x="10">Total revenue</text>"#,
                                              original: #"<text x="10">Totla revenue</text>"#)
                == #"<text x="10">Total revenue</text>"#)
        #expect(ProofreadPrompt.cleanResponse("the label is <text>Submit</text>",
                                              original: "the label is <text>Sumbit</text>")
                == "the label is <text>Submit</text>")
        #expect(ProofreadPrompt.cleanResponse("<text>", original: "<text>") == "<text>")
        // A doubled wrapper is still a leak.
        #expect(ProofreadPrompt.cleanResponse("<text>\n<text>Hello world</text>\n</text>", original: "<text>Helo world</text>")
                == "<text>Hello world</text>")
    }

    @Test func cleanResponseKeepsLiteralMarkersInsideContent() {
        // Users legitimately proofread text ABOUT markup; mid-content markers
        // are content, not leaks.
        let result = ProofreadPrompt.cleanResponse("wrap it in <text> tags, then close with </text> at the end",
                                                   original: "wrap it in <text> tags, then close with </text> at teh end")
        #expect(result == "wrap it in <text> tags, then close with </text> at the end")
    }

    @Test func cleanResponseStripsOnlyAnchoredMarkers() {
        let result = ProofreadPrompt.cleanResponse("<text>the <text> tag is common</text>", original: "x")
        #expect(result == "the <text> tag is common")
    }

    @Test func cleanResponseRestoresEdgeWhitespace() {
        let result = ProofreadPrompt.cleanResponse("the cat", original: " teh cat ")
        #expect(result == " the cat ")
    }

    @Test func allLowercaseTypedTextStaysLowercase() {
        #expect(ProofreadPrompt.cleanResponse("Idk if that's right, LOL.", original: "idk if thats rihgt, lol.",
                                              keepsLowercase: true) == "idk if that's right, lol.")
    }

    @Test func writersWhoUseCapitalsAndTheDictationPathAreUnaffected() {
        #expect(ProofreadPrompt.cleanResponse("Hey Sam, the cat", original: "hey Sam, teh cat",
                                              keepsLowercase: true) == "Hey Sam, the cat")
        #expect(ProofreadPrompt.cleanResponse("I can't come.", original: "i cant come", keepsLowercase: false)
                == "I can't come.")
    }

    @Test func dictationOutputGetsSentenceCasing() {
        #expect(ProofreadPrompt.sentenceCase("the build is fixed. i'll ship it now! is that ok?\nyes")
                == "The build is fixed. I'll ship it now! Is that ok?\nYes")
        // Already-correct text, proper nouns, decimals and words containing "i" are untouched.
        #expect(ProofreadPrompt.sentenceCase("Version 2.5 ships in denver. It is fine, i think.")
                == "Version 2.5 ships in denver. It is fine, I think.")
        #expect(ProofreadPrompt.sentenceCase("iPhone and wifi. eBay too") == "iPhone and wifi. eBay too")
    }

    @Test func lowercaseWritersWithEmphasisStayLowercase() {
        #expect(ProofreadPrompt.keepAllLowercase(original: "the new cafe is SO good, we should go sat",
                                                 corrected: "The new cafe is SO good, we should go Sat") == "the new cafe is SO good, we should go sat")
        #expect(ProofreadPrompt.keepAllLowercase(original: "hey could you reveiw my PR", corrected: "Hey, could you review my PR?")
                == "hey, could you review my PR?")
        // A writer who starts with a capital, or capitalizes a name, keeps the model's casing.
        #expect(ProofreadPrompt.keepAllLowercase(original: "I seen that movie", corrected: "I've seen that movie") == "I've seen that movie")
        #expect(ProofreadPrompt.keepAllLowercase(original: "i met Sam today", corrected: "I met Sam today") == "I met Sam today")
    }
}
