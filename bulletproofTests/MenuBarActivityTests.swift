import Foundation
import Testing
@testable import bulletproof

// Timings compressed for tests; production defaults are asserted separately.
@MainActor
struct MenuBarActivityTests {
    private func makeActivity() -> MenuBarActivity {
        MenuBarActivity(showDelay: .milliseconds(30),
                        minimumShow: .milliseconds(50),
                        failureShow: .milliseconds(60),
                        pulseInterval: .milliseconds(20))
    }

    @Test func fastOperationNeverShowsWorking() async throws {
        let activity = makeActivity()
        activity.begin()
        activity.end(success: true)
        try await Task.sleep(for: .milliseconds(60))
        #expect(activity.phase == .idle)
    }

    @Test func slowOperationShowsWorkingAfterDelay() async throws {
        let activity = makeActivity()
        activity.begin()
        #expect(activity.phase == .idle)
        try await Task.sleep(for: .milliseconds(45))
        #expect(activity.phase == .working)
        activity.end(success: true)
    }

    @Test func workingHoldsMinimumThenIdles() async throws {
        let activity = makeActivity()
        activity.begin()
        try await Task.sleep(for: .milliseconds(45))
        #expect(activity.phase == .working)
        activity.end(success: true)
        // Still visible immediately after end (minimum show).
        #expect(activity.phase == .working)
        try await Task.sleep(for: .milliseconds(80))
        #expect(activity.phase == .idle)
    }

    @Test func failureShowsFailedThenIdles() async throws {
        let activity = makeActivity()
        activity.begin()
        activity.end(success: false)
        #expect(activity.phase == .failed)
        try await Task.sleep(for: .milliseconds(90))
        #expect(activity.phase == .idle)
    }

    @Test func newBeginCancelsFailureTint() async throws {
        let activity = makeActivity()
        activity.begin()
        activity.end(success: false)
        #expect(activity.phase == .failed)
        activity.begin()
        try await Task.sleep(for: .milliseconds(45))
        #expect(activity.phase == .working)
        activity.end(success: true)
    }

    @Test func productionTimingsAreSane() {
        let activity = MenuBarActivity()
        #expect(activity.showDelay == .milliseconds(400))
        #expect(activity.minimumShow == .milliseconds(600))
        #expect(activity.failureShow == .seconds(2))
        #expect(activity.pulseInterval == .milliseconds(500))
    }

    @Test func workingPulsesTheTick() async throws {
        // MenuBarExtra labels rasterize per state change - animation must come
        // from state toggles, not from SwiftUI animation.
        let activity = makeActivity()
        activity.begin()
        try await Task.sleep(for: .milliseconds(45))
        #expect(activity.phase == .working)
        let initialTick = activity.pulseTick
        try await Task.sleep(for: .milliseconds(50))
        #expect(activity.pulseTick != initialTick)
        activity.end(success: true)
    }

    @Test func tickStopsAfterEnd() async throws {
        let activity = makeActivity()
        activity.begin()
        try await Task.sleep(for: .milliseconds(45))
        activity.end(success: true)
        try await Task.sleep(for: .milliseconds(80))
        let settledTick = activity.pulseTick
        try await Task.sleep(for: .milliseconds(50))
        #expect(activity.pulseTick == settledTick)
        #expect(activity.phase == .idle)
    }
}
