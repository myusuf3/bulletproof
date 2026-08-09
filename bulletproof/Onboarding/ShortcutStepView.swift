import SwiftUI

struct ShortcutStepView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            Text("Set your shortcut")
                .font(.title.bold())
            Text("This is the key combination you'll press to proofread selected text in any app.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            ShortcutRecorderView(combo: appState.shortcut) { appState.shortcut = $0 }
                .padding(.top, 12)

            Text("Click to change it. Needs at least one of ⌘ ⌥ ⌃.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
