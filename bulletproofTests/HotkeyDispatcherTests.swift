import AppKit
import Carbon.HIToolbox
import Testing
import UserNotifications
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

    @Test func registrationFailureMessageNamesTheChord() {
        let body = HotkeyDispatcher.registrationFailureBody(for: .default)
        #expect(body.contains(KeyCombo.default.displayString))
    }
}

private final class SpyNotificationCenter: NotificationCenterFacade, @unchecked Sendable {
    private(set) var delivered: [(title: String, body: String)] = []

    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestAuthorization() async -> Bool { true }
    func deliver(title: String, body: String) async {
        delivered.append((title, body))
    }
}

// Obscure chords so the tests never collide with the app's own registration
// (the test host registers the real shortcut at launch) - and distinct per
// test, because tests in a suite run in parallel.
@MainActor
struct HotkeyDispatcherRegistrationTests {
    @Test func claimedChordPostsNotification() async {
        let combo = KeyCombo(keyCode: UInt32(kVK_F13), modifiers: [.control, .option, .shift])
        let blocker = HotkeyManager()
        #expect(blocker.register(combo))

        let center = SpyNotificationCenter()
        let dispatcher = HotkeyDispatcher()
        dispatcher.notifier = UserNotifier(center: center)
        dispatcher.registerOrNotify(combo)

        // post() delivers on a detached task; poll rather than fixed-sleep.
        for _ in 0..<100 where center.delivered.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(center.delivered.first?.title == "Shortcut unavailable")
        #expect(center.delivered.first?.body.contains(combo.displayString) == true)
        blocker.unregister()
    }

    @Test func freeChordRegistersSilently() async {
        let combo = KeyCombo(keyCode: UInt32(kVK_F20), modifiers: [.control, .option, .shift])
        let center = SpyNotificationCenter()
        let dispatcher = HotkeyDispatcher()
        dispatcher.notifier = UserNotifier(center: center)
        dispatcher.registerOrNotify(combo)

        // Give a stray notification task a chance to land before asserting.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(center.delivered.isEmpty)
        dispatcher.unregister()
    }
}
