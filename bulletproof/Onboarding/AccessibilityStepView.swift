import SwiftUI

struct AccessibilityStepView: View {
    @State private var granted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            Text("Allow accessibility access")
                .font(.title.bold())
            Text("To proofread in other apps, bulletproof presses ⌘C and ⌘V on your behalf to read the selection and paste the correction. macOS requires your permission for that.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            if granted {
                Label {
                    Text("Access granted")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .font(.title3)
                .padding(.top, 16)
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            } else {
                Button("Grant Access") {
                    AccessibilityPermission.requestWithPrompt()
                    AccessibilityPermission.openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 16)

                Text("You can continue without it - the practice step still works, and you can grant access later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.3), value: granted)
        .task {
            while !Task.isCancelled {
                granted = AccessibilityPermission.isTrusted
                if granted { break }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
