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

    @Test func launchAtLoginFailureExplainsDevBuilds() {
        // "Operation not permitted" from SMAppService almost always means the
        // app isn't running from /Applications (dev builds, DMG, Downloads).
        let message = GeneralSettingsView.launchAtLoginFailureMessage(
            error: "The operation couldn't be completed. Operation not permitted",
            bundlePath: "/Users/me/Library/Developer/Xcode/DerivedData/x/Build/Products/Debug/bulletproof.app")
        #expect(message.contains("/Applications"))
        #expect(!message.contains("Operation not permitted"))
    }

    @Test func launchAtLoginFailureFromInstalledAppKeepsTheSystemError() {
        let message = GeneralSettingsView.launchAtLoginFailureMessage(
            error: "Something specific from macOS",
            bundlePath: "/Applications/bulletproof.app")
        #expect(message == "Something specific from macOS")
    }

    @Test func statisticsPaneIsSearchable() {
        #expect(SettingsPane.matching("statistics").contains(.statistics))
        #expect(SettingsPane.matching("latency").contains(.statistics))
        #expect(SettingsPane.matching("rejections").contains(.statistics))
        #expect(SettingsPane.matching("log").contains(.statistics))
    }
}
