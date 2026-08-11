import ServiceManagement
import SwiftUI
import UserNotifications

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var accessibilityGranted = false
    @State private var notificationsDenied = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

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

            if notificationsDenied {
                Section {
                    Label {
                        Text("Notifications are off, so proofreading errors can't be shown. Turn them on to see why a proofread failed.")
                    } icon: {
                        Image(systemName: "bell.slash.fill")
                            .foregroundStyle(.orange)
                    }
                    Button("Open Notification Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                    }
                }
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, wantsEnabled in
                        do {
                            if wantsEnabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            launchAtLoginError = nil
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                            launchAtLoginError = error.localizedDescription
                        }
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("How to Use bulletproof…") {
                    OnboardingWindowController.shared.show()
                }
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                accessibilityGranted = AccessibilityPermission.isTrusted
                notificationsDenied = await UNUserNotificationCenter.current()
                    .notificationSettings().authorizationStatus == .denied
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
