import Testing
@testable import bulletproof

struct SettingsPaneTests {
    @Test func emptyQueryReturnsAllPanes() {
        #expect(SettingsPane.matching("") == SettingsPane.allCases)
        #expect(SettingsPane.matching("   ") == SettingsPane.allCases)
    }

    @Test func matchesByTitle() {
        #expect(SettingsPane.matching("mod") == [.models])
        #expect(SettingsPane.matching("GENERAL") == [.general])
    }

    @Test func matchesByKeyword() {
        // Users search for what they want, not what we named the pane.
        #expect(SettingsPane.matching("permission").contains(.shortcut))
        #expect(SettingsPane.matching("update").contains(.about))
        #expect(SettingsPane.matching("hotkey").contains(.shortcut))
        #expect(SettingsPane.matching("download").contains(.models))
        #expect(SettingsPane.matching("apple intelligence").contains(.engine))
        #expect(SettingsPane.matching("login").contains(.general))
    }

    @Test func gibberishMatchesNothing() {
        #expect(SettingsPane.matching("xyzzy").isEmpty)
    }
}
