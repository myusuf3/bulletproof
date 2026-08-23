import AppKit

/// The app's sound palette, all quiet system sounds with distinct meanings:
/// steps pop, permission granting purrs, the practice win rings, finishing
/// is a small fanfare, and a landed correction ticks. Onboarding sounds are
/// unconditional (rare, first-run ceremony); the correction tick is the only
/// recurring one, so it alone is user-configurable.
@MainActor enum UISound {
    static func stepForward() {
        play("Pop", volume: 0.32)
    }

    static func stepBack() {
        play("Pop", volume: 0.2)
    }

    /// Accessibility granted mid-walkthrough.
    static func granted() {
        play("Purr", volume: 0.3)
    }

    /// The practice proofread landed - the earned moment.
    static func practiceSuccess() {
        play("Glass", volume: 0.35)
    }

    /// Walkthrough completed.
    static func finished() {
        play("Hero", volume: 0.25)
    }

    /// A correction landed in place. Fires on every proofread, so it is
    /// gated by the Settings toggle at the call sites.
    static func correctionApplied() {
        play("Tink", volume: 0.3)
    }

    private static func play(_ name: String, volume: Float) {
        guard let sound = NSSound(named: name) else { return }
        sound.volume = volume
        sound.play()
    }
}
