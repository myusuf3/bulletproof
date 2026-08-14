import Foundation
import Testing
@testable import bulletproof

struct FocusGuardTests {
    // MARK: - Secure fields

    @Test func secureSubroleIsDetected() {
        #expect(FocusGuard.isSecureField(subrole: "AXSecureTextField",
                                         roleDescription: nil, title: nil,
                                         description: nil, placeholder: nil))
    }

    @Test func secureRoleDescriptionIsDetected() {
        // The only place NSSecureTextField announces itself in some hosts.
        #expect(FocusGuard.isSecureField(subrole: nil,
                                         roleDescription: "secure text field", title: nil,
                                         description: nil, placeholder: nil))
    }

    @Test func sensitiveMarkersAreDetectedInAnyTextAttribute() {
        for marker in ["Password", "CVV", "cvc", "one-time code", "Verification Code",
                       "card number", "Social Security", "passcode", "PIN"] {
            #expect(FocusGuard.isSecureField(subrole: nil, roleDescription: nil,
                                             title: marker, description: nil, placeholder: nil),
                    "title \(marker) should be detected")
            #expect(FocusGuard.isSecureField(subrole: nil, roleDescription: nil,
                                             title: nil, description: nil, placeholder: marker),
                    "placeholder \(marker) should be detected")
        }
    }

    @Test func ordinaryFieldsAreNotFlagged() {
        #expect(!FocusGuard.isSecureField(subrole: "AXSearchField",
                                          roleDescription: "text field", title: "Search",
                                          description: "message body", placeholder: "Reply…"))
        // "pin" must match as a word, not inside e.g. "shipping" or "spinner".
        #expect(!FocusGuard.isSecureField(subrole: nil, roleDescription: nil,
                                          title: "Shipping address", description: "spinner",
                                          placeholder: nil))
    }

    // MARK: - Terminals

    @Test func knownTerminalBundleIDsAreExcluded() {
        for id in ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
                   "net.kovidgoyal.kitty", "com.github.wez.wezterm", "com.mitchellh.ghostty"] {
            #expect(FocusGuard.isTerminal(bundleID: id, domClasses: []))
        }
    }

    @Test func xtermDOMClassMarksVSCodeIntegratedTerminal() {
        // VS Code's editor and integrated terminal share one process; only
        // the DOM class list tells them apart.
        #expect(FocusGuard.isTerminal(bundleID: "com.microsoft.VSCode",
                                      domClasses: ["xterm-screen", "monaco-thing"]))
    }

    @Test func editorsAndOrdinaryAppsAreNotTerminals() {
        #expect(!FocusGuard.isTerminal(bundleID: "com.microsoft.VSCode",
                                       domClasses: ["monaco-editor", "view-lines"]))
        #expect(!FocusGuard.isTerminal(bundleID: "com.apple.Notes", domClasses: []))
        #expect(!FocusGuard.isTerminal(bundleID: nil, domClasses: []))
    }

    @Test func everyBlockReasonHasUserMessage() {
        for reason in FocusGuard.BlockReason.allCases {
            #expect(!reason.message.isEmpty)
        }
    }
}
