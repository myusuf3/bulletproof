import SwiftUI

/// The status item, drawn from the template images in Assets.xcassets:
/// MenuBarDefault at rest, MenuBarDictation while hold-to-talk is listening or
/// transcribing, and MenuBarProofreading alternating with the default glyph
/// while a proofread is in flight, and MenuBarFailed briefly after a failure.
/// The blink is state-driven (see MenuBarActivity.pulseTick) because
/// SwiftUI animations never tick inside a MenuBarExtra label.
struct MenuBarIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let activity = AppState.shared.activity
        Image(Self.imageName(for: activity, reduceMotion: reduceMotion))
            .renderingMode(.template)
            .accessibilityLabel(Self.accessibilityLabel(for: activity))
    }

    static func imageName(for activity: MenuBarActivity, reduceMotion: Bool) -> String {
        imageName(phase: activity.phase, dictating: activity.dictating,
                  pulseTick: activity.pulseTick, reduceMotion: reduceMotion)
    }

    /// Pure mapping, unit-tested. Reduce Motion: a steady proofreading glyph instead of blinking.
    nonisolated static func imageName(phase: MenuBarActivity.Phase, dictating: Bool,
                                      pulseTick: Bool, reduceMotion: Bool) -> String {
        if dictating { return "MenuBarDictation" }
        switch phase {
        case .working: return reduceMotion || pulseTick ? "MenuBarProofreading" : "MenuBarDefault"
        case .idle: return "MenuBarDefault"
        case .failed: return "MenuBarFailed"
        }
    }

    private static func accessibilityLabel(for activity: MenuBarActivity) -> String {
        if activity.dictating { return "bulletproof - dictating" }
        switch activity.phase {
        case .idle: return "bulletproof"
        case .working: return "bulletproof - proofreading"
        case .failed: return "bulletproof - proofread failed"
        }
    }
}
