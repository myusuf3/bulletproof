import Foundation
import Testing
@testable import bulletproof

@MainActor
struct AppPolicyStoreTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "policy-test-\(UUID().uuidString)")!
    }

    @Test func unknownAppsGetTheDefaultPolicy() {
        let store = AppPolicyStore(defaults: freshDefaults())
        #expect(store.policy(for: "com.example.editor") == TargetPolicy())
        #expect(store.policy(for: nil) == TargetPolicy())
    }

    @Test func policiesPersistAcrossRelaunch() {
        let defaults = freshDefaults()
        let store = AppPolicyStore(defaults: defaults)
        store.setPolicy(TargetPolicy(proofreadingDisabled: true), for: "com.apple.Xcode",
                        displayName: "Xcode")
        let relaunched = AppPolicyStore(defaults: defaults)
        #expect(relaunched.policy(for: "com.apple.Xcode").proofreadingDisabled)
        #expect(relaunched.displayNames["com.apple.Xcode"] == "Xcode")
    }

    @Test func terminalAllowancePersists() {
        let defaults = freshDefaults()
        AppPolicyStore(defaults: defaults)
            .setPolicy(TargetPolicy(allowDespiteTerminal: true), for: "net.kovidgoyal.kitty",
                       displayName: "kitty")
        #expect(AppPolicyStore(defaults: defaults)
            .policy(for: "net.kovidgoyal.kitty").allowDespiteTerminal)
    }

    @Test func defaultPolicyRowsAreDropped() {
        // Toggling back to defaults must not leave ghost entries behind.
        let defaults = freshDefaults()
        let store = AppPolicyStore(defaults: defaults)
        store.setPolicy(TargetPolicy(proofreadingDisabled: true), for: "com.a.b", displayName: "B")
        store.setPolicy(TargetPolicy(), for: "com.a.b", displayName: "B")
        #expect(AppPolicyStore(defaults: defaults).policies.isEmpty)
    }
}

struct PolicyResolutionTests {
    @Test func secureFieldsAreNeverOverridable() {
        // Even an explicitly enabled app must not expose password fields.
        let permissive = TargetPolicy(proofreadingDisabled: false, allowDespiteTerminal: true)
        #expect(FocusGuard.policyBlock(secureField: true, terminal: false, policy: permissive)
                == .secureField)
        #expect(FocusGuard.policyBlock(secureField: true, terminal: true, policy: permissive)
                == .secureField)
    }

    @Test func userDisableBeatsEverythingExceptSecureFields() {
        let disabled = TargetPolicy(proofreadingDisabled: true)
        #expect(FocusGuard.policyBlock(secureField: false, terminal: false, policy: disabled)
                == .disabledByUser)
        #expect(FocusGuard.policyBlock(secureField: false, terminal: true, policy: disabled)
                == .disabledByUser)
    }

    @Test func terminalsBlockByDefaultButAreOverridable() {
        #expect(FocusGuard.policyBlock(secureField: false, terminal: true, policy: TargetPolicy())
                == .terminal)
        #expect(FocusGuard.policyBlock(secureField: false, terminal: true,
                                       policy: TargetPolicy(allowDespiteTerminal: true)) == nil)
    }

    @Test func ordinaryAppsWithDefaultPolicyPass() {
        #expect(FocusGuard.policyBlock(secureField: false, terminal: false, policy: TargetPolicy())
                == nil)
    }

    @Test func disabledByUserHasDistinctMessageAndTelemetry() {
        #expect(FocusGuard.BlockReason.disabledByUser.message.contains("Settings"))
        #expect(FocusGuard.BlockReason.disabledByUser.telemetryReason == "disabled-by-user")
    }

    @Test func knownTerminalsAreExposedForTheAppsPane() {
        #expect(FocusGuard.isKnownTerminal(bundleID: "net.kovidgoyal.kitty"))
        #expect(!FocusGuard.isKnownTerminal(bundleID: "com.apple.Notes"))
        #expect(!FocusGuard.isKnownTerminal(bundleID: nil))
    }
}
