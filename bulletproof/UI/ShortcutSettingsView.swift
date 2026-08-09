import SwiftUI

struct ShortcutSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var accessibilityGranted = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Proofread selection") {
                    ShortcutRecorderView(combo: appState.shortcut) { appState.shortcut = $0 }
                }
            } footer: {
                Text("Press the shortcut with text selected in any app to proofread it in place.")
            }

            Section {
                if accessibilityGranted {
                    Label {
                        Text("Accessibility access granted")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    Label {
                        Text("Accessibility access is required for the shortcut to read and replace selected text.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Button("Open System Settings") {
                        AccessibilityPermission.openSystemSettings()
                    }
                }
            }

            Section {
                Button("How to Use bulletproof…") {
                    OnboardingWindowController.shared.show()
                }
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                accessibilityGranted = AccessibilityPermission.isTrusted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
