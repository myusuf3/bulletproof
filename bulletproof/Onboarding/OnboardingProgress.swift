import Foundation

/// Versioned onboarding progress. A Bool "seen" flag stamped on any window
/// close counted mid-flow ⌘W - and the Accessibility-grant relaunch - as
/// completed; a version plus a monotonic step survive both, and bumping the
/// version re-shows a revamped walkthrough.
@MainActor final class OnboardingProgress {
    /// Bump to show a revamped walkthrough to existing users.
    static let currentVersion = 1

    private static let versionKey = "onboardingCompletedVersion"
    private static let stepKey = "onboardingProgressStep"
    private static let legacyKey = "hasSeenOnboarding"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Users who finished the old Bool-flag onboarding must not see the
        // walkthrough again just because the storage changed.
        if defaults.bool(forKey: Self.legacyKey), defaults.integer(forKey: Self.versionKey) == 0 {
            defaults.set(Self.currentVersion, forKey: Self.versionKey)
        }
    }

    var needsOnboarding: Bool {
        defaults.integer(forKey: Self.versionKey) < Self.currentVersion
    }

    /// Where a relaunched or reopened walkthrough resumes.
    var resumeStep: Int {
        defaults.integer(forKey: Self.stepKey)
    }

    /// Monotonic - navigating Back never loses progress.
    func advance(to step: Int) {
        guard step > resumeStep else { return }
        defaults.set(step, forKey: Self.stepKey)
    }

    /// Stamped by the final button only, never by a closing window.
    func complete() {
        defaults.set(Self.currentVersion, forKey: Self.versionKey)
        defaults.set(0, forKey: Self.stepKey)
    }
}
