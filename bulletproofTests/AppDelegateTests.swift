import Foundation
import Testing
@testable import bulletproof

struct TestHostDetectionTests {
    @Test func xcTestEnvironmentIsDetected() {
        #expect(AppDelegate.isTestHost(environment: ["XCTestSessionIdentifier": "ABC"]))
        #expect(AppDelegate.isTestHost(environment: ["XCTestConfigurationFilePath": "/tmp/x"]))
    }

    @Test func normalLaunchIsNot() {
        #expect(!AppDelegate.isTestHost(environment: [:]))
        // The services e2e harness runs the real app with env overrides - it
        // must still get real launch behavior.
        #expect(!AppDelegate.isTestHost(environment: ["BULLETPROOF_FAKE_ENGINE": "1"]))
    }

    @Test func thisVeryTestRunIsDetected() {
        // Proves the real environment of a hosted test run trips the guard.
        #expect(AppDelegate.isTestHost(environment: ProcessInfo.processInfo.environment))
    }
}
