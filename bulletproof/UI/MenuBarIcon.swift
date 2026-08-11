import SwiftUI

/// The status item: blinks between outline and filled seal while a proofread
/// is in flight, and shows an orange exclamation seal briefly on failure.
/// The blink is state-driven (see MenuBarActivity.pulseTick) because SwiftUI
/// animations never tick inside a MenuBarExtra label.
struct MenuBarIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let activity = AppState.shared.activity
        Image(systemName: symbolName(for: activity))
            .foregroundStyle(activity.phase == .failed ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            .accessibilityLabel(accessibilityLabel(for: activity.phase))
    }

    private func symbolName(for activity: MenuBarActivity) -> String {
        switch activity.phase {
        case .idle:
            "checkmark.seal"
        case .working:
            // Reduce Motion: steady filled seal instead of blinking.
            reduceMotion || activity.pulseTick ? "checkmark.seal.fill" : "checkmark.seal"
        case .failed:
            "exclamationmark.seal.fill"
        }
    }

    private func accessibilityLabel(for phase: MenuBarActivity.Phase) -> String {
        switch phase {
        case .idle: "bulletproof"
        case .working: "bulletproof - proofreading"
        case .failed: "bulletproof - proofread failed"
        }
    }
}
