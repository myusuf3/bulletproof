import Testing
@testable import bulletproof

struct CodeSpanRestorerTests {
    private func restore(_ original: String, _ corrected: String) -> String {
        CodeSpanRestorer.restore(original: original, corrected: corrected)
    }

    @Test func unwrappedCodeGetsItsBackticksBack() {
        #expect(restore("handle nil `userID` in `Cache.load()` so it dosent crash",
                        "handle nil userID in Cache.load() so it doesn't crash")
                == "handle nil `userID` in `Cache.load()` so it doesn't crash")
    }

    @Test func quotedCodeBecomesBacktickedAgain() {
        #expect(restore("The `--dry-run` flag prints evrything", "The \"--dry-run\" flag prints everything")
                == "The `--dry-run` flag prints everything")
    }

    @Test func editsInsideCodeAreUndone() {
        #expect(restore("accepts `-o, --output <path>` and its fine", "accepts `-o, --output<path>` and it's fine")
                == "accepts `-o, --output <path>` and it's fine")
    }

    @Test func onlyWholeWordsOutsideCodeAreWrapped() {
        // "id" inside "valid" must not be wrapped.
        #expect(restore("set `id` here", "A valid value is set here") == "A valid value is set here")
    }

    @Test func textWithoutCodeIsUntouched() {
        #expect(restore("teh cat", "the cat") == "the cat")
        #expect(restore("use `x`", "use `x`") == "use `x`")
    }

    @Test func cleanResponseRestoresCode() {
        #expect(ProofreadPrompt.cleanResponse("Run the npm test command", original: "Run teh `npm test` command")
                == "Run the `npm test` command")
    }
}
