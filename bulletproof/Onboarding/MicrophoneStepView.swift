import SwiftUI

struct MicrophoneStepView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var status = MicrophonePermission.status

    var body: some View {
        VStack(spacing: 16) {
            Text("Talk instead of type")
                .font(.title.bold())
            Text("Hold the dictation shortcut in any app and speak - bulletproof types what you say. It listens only while you hold the keys, and transcribes on this Mac.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            HStack(spacing: 6) {
                ForEach(appState.dictationShortcut.modifierSymbols, id: \.self) { KeycapView(symbol: $0) }
                KeycapView(symbol: KeyCombo.keySymbol(for: appState.dictationShortcut.keyCode))
            }
            .padding(.top, 6)

            switch status {
            case .granted:
                VStack(spacing: 8) {
                    MicrophoneMeter(deviceUID: appState.microphoneUID)
                        .frame(width: 220, height: 34)
                    Label("Microphone ready - say something", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 10)
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            case .notDetermined:
                Button("Allow Microphone") {
                    Task {
                        if await MicrophonePermission.request() { UISound.granted() }
                        status = MicrophonePermission.status
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 10)
                skipNote
            case .denied:
                Button("Open System Settings") {
                    MicrophonePermission.openSystemSettings()
                }
                .controlSize(.large)
                .padding(.top, 10)
                Text("Microphone access is off. Turn on bulletproof in Privacy & Security > Microphone to dictate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.3), value: status)
        .task {
            // Picks up a grant made in System Settings while this step waits.
            while !Task.isCancelled && status != .granted {
                try? await Task.sleep(for: .seconds(1))
                status = MicrophonePermission.status
            }
        }
    }

    private var skipNote: some View {
        Text("Dictation is optional - you can continue without it and allow the microphone later in Settings.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
    }
}
