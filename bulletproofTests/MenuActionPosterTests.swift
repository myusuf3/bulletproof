import Testing
@testable import bulletproof

struct MenuActionPosterTests {
    @Test func plainCommandKeyEquivalentMatches() {
        #expect(MenuActionPoster.matches(keyEquivalent: "V", cmdChar: "V", cmdModifiers: 0))
        #expect(MenuActionPoster.matches(keyEquivalent: "C", cmdChar: "C", cmdModifiers: 0))
    }

    @Test func matchingIsCaseInsensitive() {
        #expect(MenuActionPoster.matches(keyEquivalent: "V", cmdChar: "v", cmdModifiers: 0))
    }

    @Test func extraModifiersDoNotMatch() {
        // ⇧⌘V (Paste and Match Style) must never be mistaken for Paste.
        #expect(!MenuActionPoster.matches(keyEquivalent: "V", cmdChar: "V", cmdModifiers: 1))
        #expect(!MenuActionPoster.matches(keyEquivalent: "V", cmdChar: "V", cmdModifiers: 2))
    }

    @Test func differentOrMissingKeyEquivalentDoesNotMatch() {
        #expect(!MenuActionPoster.matches(keyEquivalent: "V", cmdChar: "C", cmdModifiers: 0))
        #expect(!MenuActionPoster.matches(keyEquivalent: "V", cmdChar: nil, cmdModifiers: 0))
        #expect(!MenuActionPoster.matches(keyEquivalent: "V", cmdChar: "V", cmdModifiers: nil))
    }
}
