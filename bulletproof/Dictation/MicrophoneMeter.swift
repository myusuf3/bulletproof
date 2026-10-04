import SwiftUI

/// Live waveform from the chosen input while on screen, so users can see
/// the mic hears them before relying on dictation. Nothing is recorded.
/// Show only once microphone access is granted.
struct MicrophoneMeter: View {
    let deviceUID: String?
    var tint: Color = .accentColor
    @State private var recorder = AudioRecorder()
    @State private var unavailable = false

    var body: some View {
        ZStack {
            WaveformView(levels: recorder.levels.levels, tint: tint)
                .opacity(unavailable ? 0.3 : 1)
            if unavailable {
                Text("Microphone unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: deviceUID) {
            do {
                try recorder.start(deviceUID: deviceUID, keepSamples: false)
                unavailable = false
            } catch {
                unavailable = true
            }
        }
        .onDisappear { _ = recorder.stop() }
    }
}
