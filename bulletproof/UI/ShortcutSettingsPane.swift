import SwiftUI
import UserNotifications

struct ShortcutSettingsPane: View {
    @Environment(AppState.self) private var appState
    @State private var accessibilityGranted = false
    @State private var notificationsDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard {
                SettingRow(title: "Proofread selection",
                           description: "Press this shortcut with text selected in any app to fix it in place.") {
                    ShortcutRecorderView(combo: appState.shortcut) { appState.shortcut = $0 }
                }
            }

            SettingsCard(header: "Permissions") {
                SettingRow(title: "Accessibility",
                           description: accessibilityGranted
                               ? "Granted. The shortcut can read and replace selected text."
                               : "Required for the shortcut to read and replace selected text in other apps.") {
                    if accessibilityGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title3)
                    } else {
                        Button("Open System Settings") {
                            AccessibilityPermission.openSystemSettings()
                        }
                    }
                }
                SettingDivider()
                SettingRow(title: "Notifications",
                           description: notificationsDenied
                               ? "Off - proofreading errors can't be shown. Turn them on to see why a proofread failed."
                               : "Used only to explain failures and confirm clipboard copies.") {
                    if notificationsDenied {
                        Button("Open Notification Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                        }
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title3)
                    }
                }
            }

            SettingsCard(header: "Also available") {
                SettingRow(title: "Right-click menu",
                           description: "Select text in any app, then choose Services > Proofread. No permissions needed.") {
                    EmptyView()
                }
                SettingDivider()
                SettingRow(title: "Shortcuts app",
                           description: "The \"Proofread Text\" action works in Shortcuts, Spotlight, and Siri.") {
                    EmptyView()
                }
            }
        }
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
