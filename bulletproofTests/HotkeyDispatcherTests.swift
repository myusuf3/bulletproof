import Testing
@testable import bulletproof

struct HotkeyRouteTests {
    @Test func suspendedIgnoresEverything() {
        #expect(HotkeyDispatcher.route(isSuspended: true, appIsActive: true, hasPracticeHandler: true) == .ignored)
        #expect(HotkeyDispatcher.route(isSuspended: true, appIsActive: false, hasPracticeHandler: false) == .ignored)
    }

    @Test func practiceConsumesEveryPressWhileAppIsActive() {
        // A press during ANY practice stage must never fall through to the
        // real CGEvent flow - that would post synthetic keystrokes into the
        // onboarding window (or prompt for accessibility mid-tutorial).
        #expect(HotkeyDispatcher.route(isSuspended: false, appIsActive: true, hasPracticeHandler: true) == .practice)
    }

    @Test func backgroundAppRunsGlobalFlowEvenMidOnboarding() {
        #expect(HotkeyDispatcher.route(isSuspended: false, appIsActive: false, hasPracticeHandler: true) == .global)
    }

    @Test func normalOperationRunsGlobalFlow() {
        #expect(HotkeyDispatcher.route(isSuspended: false, appIsActive: true, hasPracticeHandler: false) == .global)
        #expect(HotkeyDispatcher.route(isSuspended: false, appIsActive: false, hasPracticeHandler: false) == .global)
    }
}
