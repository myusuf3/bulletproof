import SwiftUI

/// The status item: pulses while a proofread is in flight, blips orange on
/// failure. Fast operations never animate (see MenuBarActivity timings).
struct MenuBarIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let phase = AppState.shared.activity.phase
        Image(systemName: symbolName(for: phase))
            .symbolEffect(.variableColor.iterative,
                          isActive: !reduceMotion && phase == .working)
            .foregroundStyle(phase == .failed ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            .accessibilityLabel(accessibilityLabel(for: phase))
    }

    private func symbolName(for phase: MenuBarActivity.Phase) -> String {
        switch phase {
        case .idle: "checkmark.seal"
        // Filled variant carries the state change under Reduce Motion.
        case .working: reduceMotion ? "checkmark.seal.fill" : "checkmark.seal"
        case .failed: "exclamationmark.seal.fill"
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
