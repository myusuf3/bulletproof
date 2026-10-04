import AVFoundation
import Speech
import SwiftUI

struct DictationSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var microphoneStatus = MicrophonePermission.status
    @State private var devices = AudioInputDevices.all()

    var body: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard {
                SettingRow(title: "Hold to dictate",
                           description: "Hold this shortcut anywhere and speak. Let go, and what you said is typed at the cursor.") {
                    ShortcutRecorderView(combo: appState.dictationShortcut, slot: .dictation) {
                        appState.dictationShortcut = $0
                    }
                }
                SettingDivider()
                SettingRow(title: "Proofread dictation",
                           description: "Runs what you said through your proofreading engine before it's typed. Adds a moment.") {
                    Toggle("", isOn: $appState.proofreadDictation)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsCard(header: "Speech-to-text model") {
                SettingRow(title: "Model", description: modelDescription) {
                    Picker("", selection: $appState.speechModel) {
                        ForEach(SpeechModelChoice.allCases, id: \.self) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                if appState.speechModel == .whistle {
                    SettingDivider()
                    WhistleDownloadRow(manager: appState.downloads)
                }
            }

            SettingsCard(header: "Microphone") {
                SettingRow(title: "Input",
                           description: "The microphone dictation listens to.") {
                    Picker("", selection: $appState.microphoneUID) {
                        Text("System Default").tag(String?.none)
                        if !devices.isEmpty { Divider() }
                        ForEach(devices) { device in
                            Text(device.name).tag(Optional(device.uid))
                        }
                        if let uid = appState.microphoneUID, !devices.contains(where: { $0.uid == uid }) {
                            Text("Disconnected microphone").tag(Optional(uid))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                SettingDivider()
                permissionRow
                if microphoneStatus == .granted {
                    SettingDivider()
                    SettingRow(title: "Test", description: "Speak - the wave should move with your voice.") {
                        MicrophoneMeter(deviceUID: appState.microphoneUID)
                            .frame(width: 180, height: 28)
                    }
                }
            }
        }
        .onChange(of: appState.speechModel) { _, model in
            // Choosing a model is the intent to use it: fetch what it needs.
            switch model {
            case .whistle:
                if case .notInstalled = appState.downloads.state(of: ModelCatalog.whistle) {
                    appState.downloads.download(ModelCatalog.whistle)
                }
            case .appleSpeech:
                Task { await AppleSpeechEngine().prewarm() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in
            devices = AudioInputDevices.all()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in
            devices = AudioInputDevices.all()
        }
        .task {
            while !Task.isCancelled {
                microphoneStatus = MicrophonePermission.status
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var modelDescription: String {
        switch appState.speechModel {
        case .appleSpeech:
            SpeechTranscriber.isAvailable
                ? "Built into macOS. Language data downloads once, the first time you dictate."
                : "Apple Speech isn't available on this Mac - choose Whistle instead."
        case .whistle:
            "Cactus Whistle: a 17 MB model, fully offline. English, German, French, Spanish, Italian, Dutch, and Polish, detected automatically."
        }
    }

    @ViewBuilder
    private var permissionRow: some View {
        switch microphoneStatus {
        case .granted:
            SettingRow(title: "Microphone access",
                       description: "Granted. bulletproof listens only while you hold the shortcut.") {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }
        case .notDetermined:
            SettingRow(title: "Microphone access",
                       description: "Required for dictation. macOS will ask once.") {
                Button("Allow Microphone…") {
                    Task { _ = await MicrophonePermission.request() }
                }
            }
        case .denied:
            SettingRow(title: "Microphone access",
                       description: "Off - dictation can't hear you. Turn on bulletproof in Privacy & Security > Microphone.") {
                Button("Open System Settings") {
                    MicrophonePermission.openSystemSettings()
                }
            }
        }
    }
}

private struct WhistleDownloadRow: View {
    let manager: ModelDownloadManager

    var body: some View {
        let model = ModelCatalog.whistle
        switch manager.state(of: model) {
        case .installed(let bytes):
            SettingRow(title: "Whistle is ready",
                       description: "\(format(bytes)) on disk. Manage it in Models.") {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }
        case .downloading(let completed, let total):
            SettingRow(title: "Downloading Whistle…",
                       description: "\(format(completed)) of \(format(total))") {
                HStack(spacing: 8) {
                    ProgressView(value: total > 0 ? Double(completed) / Double(total) : 0)
                        .frame(width: 100)
                    Button("Cancel") { manager.cancel(model) }
                }
            }
        case .notInstalled:
            SettingRow(title: "Whistle isn't downloaded",
                       description: "One \(format(model.approxDownloadBytes)) download from Hugging Face.") {
                Button("Download") { manager.download(model) }
            }
        case .failed(let message):
            SettingRow(title: "Download failed", description: message) {
                Button("Try Again") { manager.download(model) }
            }
        }
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
