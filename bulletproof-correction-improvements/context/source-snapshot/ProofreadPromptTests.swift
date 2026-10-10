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
}
