import Foundation
import Testing
@testable import bulletproof

@MainActor
struct OnboardingProgressTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "onboarding-test-\(UUID().uuidString)")!
    }

    @Test func freshInstallNeedsOnboarding() {
        let progress = OnboardingProgress(defaults: freshDefaults())
        #expect(progress.needsOnboarding)
        #expect(progress.resumeStep == 0)
    }

    @Test func legacyBoolFlagMigratesToCompleted() {
        // Users who finished the old hasSeenOnboarding flow must not see the
        // walkthrough again just because the storage changed.
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hasSeenOnboarding")
        let progress = OnboardingProgress(defaults: defaults)
        #expect(!progress.needsOnboarding)
    }

    @Test func closingMidFlowDoesNotComplete() {
        // The old bug: any window close - including the Accessibility-grant
        // relaunch - stamped onboarding as seen.
        let defaults = freshDefaults()
        let progress = OnboardingProgress(defaults: defaults)
        progress.advance(to: 2)
        #expect(OnboardingProgress(defaults: defaults).needsOnboarding)
        #expect(OnboardingProgress(defaults: defaults).resumeStep == 2)
    }

    @Test func advanceIsMonotonic() {
        let progress = OnboardingProgress(defaults: freshDefaults())
        progress.advance(to: 3)
        progress.advance(to: 1)
        #expect(progress.resumeStep == 3)
    }

    @Test func completeStampsVersionAndClearsStep() {
        let defaults = freshDefaults()
        let progress = OnboardingProgress(defaults: defaults)
        progress.advance(to: 4)
        progress.complete()
        #expect(!progress.needsOnboarding)
        #expect(OnboardingProgress(defaults: defaults).resumeStep == 0)
    }

    @Test func versionBumpReshowsWalkthrough() {
        let defaults = freshDefaults()
        // A completion stamped by an older walkthrough version.
        defaults.set(OnboardingProgress.currentVersion - 1, forKey: "onboardingCompletedVersion")
        #expect(OnboardingProgress(defaults: defaults).needsOnboarding)
    }
}
