import SwiftUI

/// On-demand mic check: Test listens for a few seconds with a live wave,
/// then releases the mic. It never runs just because a window is open -
/// the menu bar's mic indicator would stay lit long after the user looked
/// away. Nothing is recorded. Show only once microphone access is granted.
struct MicrophoneMeter: View {
    let deviceUID: String?
    var tint: Color = .accentColor
    nonisolated static let testDuration: Duration = .seconds(8)

    @State private var recorder = AudioRecorder()
    @State private var testing = false
    @State private var unavailable = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                WaveformView(levels: recorder.levels.levels, tint: tint)
                    .opacity(testing ? 1 : 0.35)
                if unavailable {
                    Text("Microphone unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button(testing ? "Stop" : "Test") { testing.toggle() }
                .fixedSize()
        }
        // Restarts on a device change mid-test; cancellation (Stop, device
        // change, view gone) falls through to the stop below.
        .task(id: [testing ? "on" : "off", deviceUID ?? ""]) {
            guard testing else { return }
            do {
                try recorder.start(deviceUID: deviceUID, keepSamples: false)
                unavailable = false
            } catch {
                unavailable = true
                testing = false
                return
            }
            try? await Task.sleep(for: Self.testDuration)
            stopListening()
            if !Task.isCancelled { testing = false }
        }
        .onDisappear {
            stopListening()
            testing = false
        }
    }

    private func stopListening() {
        _ = recorder.stop()
        recorder.levels.reset()
    }
}
