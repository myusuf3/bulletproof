import Foundation
import Testing
@testable import bulletproof

// Timings compressed for tests; production defaults are asserted separately.
// Assertions poll rather than racing fixed sleeps - CI runners can delay
// task scheduling by hundreds of milliseconds. Serialized because parallel
// main-actor tests starve each other on slow runners: three consecutive CI
// runs timed out waiting on 30ms tasks with the suite parallel.
@Suite(.serialized)
@MainActor
struct MenuBarActivityTests {
    private func makeActivity() -> MenuBarActivity {
        MenuBarActivity(showDelay: .milliseconds(30),
                        minimumShow: .milliseconds(300),
                        failureShow: .milliseconds(60),
                        pulseInterval: .milliseconds(20))
    }

    private func waitFor(_ condition: @autoclosure () -> Bool,
                         timeout: Duration = .seconds(15)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test func fastOperationNeverShowsWorking() async throws {
        let activity = makeActivity()
        activity.begin()
        activity.end(success: true)
        // end() invalidates the delayed-show task synchronously, so this holds
        // no matter how late the scheduler runs it.
        try await Task.sleep(for: .milliseconds(100))
        #expect(activity.phase == .idle)
    }

    @Test func slowOperationShowsWorkingAfterDelay() async throws {
        let activity = makeActivity()
        activity.begin()
        #expect(activity.phase == .idle)
        #expect(await waitFor(activity.phase == .working))
        activity.end(success: true)
    }

    @Test func workingHoldsMinimumThenIdles() async throws {
        let activity = makeActivity()
        activity.begin()
        #expect(await waitFor(activity.phase == .working))
        activity.end(success: true)
        // Still visible immediately after end (minimum show).
        #expect(activity.phase == .working)
        #expect(await waitFor(activity.phase == .idle))
    }

    @Test func failureShowsFailedThenIdles() async throws {
        let activity = makeActivity()
        activity.begin()
        activity.end(success: false)
        #expect(activity.phase == .failed)
        #expect(await waitFor(activity.phase == .idle))
    }

    @Test func newBeginCancelsFailureTint() async throws {
        let activity = makeActivity()
        activity.begin()
        activity.end(success: false)
        #expect(activity.phase == .failed)
        activity.begin()
        #expect(await waitFor(activity.phase == .working))
        activity.end(success: true)
    }

    @Test func workingPulsesTheTick() async throws {
        let activity = makeActivity()
        activity.begin()
        #expect(await waitFor(activity.phase == .working))
        let initialTick = activity.pulseTick
        #expect(await waitFor(activity.pulseTick != initialTick))
        activity.end(success: true)
    }

    @Test func tickStopsAfterEnd() async throws {
        let activity = makeActivity()
        activity.begin()
        #expect(await waitFor(activity.phase == .working))
        activity.end(success: true)
        #expect(await waitFor(activity.phase == .idle))
        // end() cancels the ticker synchronously via the generation counter,
        // so any further toggle would be a real bug, not a race.
        let settledTick = activity.pulseTick
        try await Task.sleep(for: .milliseconds(100))
        #expect(activity.pulseTick == settledTick)
    }

    @Test func productionTimingsAreSane() {
        let activity = MenuBarActivity()
        #expect(activity.showDelay == .milliseconds(400))
        #expect(activity.minimumShow == .milliseconds(600))
        #expect(activity.failureShow == .seconds(2))
        #expect(activity.pulseInterval == .milliseconds(500))
    }
}
