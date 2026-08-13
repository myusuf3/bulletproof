import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard {
                SettingRow(title: "Launch at login",
                           description: "Start bulletproof automatically so proofreading is always one keystroke away.") {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
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
                }
                if let launchAtLoginError {
                    SettingDivider()
                    SettingRow(title: "", description: launchAtLoginError) { EmptyView() }
                }
            }

            SettingsCard(header: "Learn") {
                SettingRow(title: "Onboarding walkthrough",
                           description: "Replay the setup guide: shortcut, permissions, and a practice run.") {
                    Button("How to Use bulletproof…") {
                        OnboardingWindowController.shared.show()
                    }
                }
            }

            if appState.history.wordsProofread > 0 {
                SettingsCard(header: "Privacy") {
                    SettingRow(title: "\(appState.history.wordsProofread.formatted()) words proofread",
                               description: "Every one processed on this Mac. Nothing has ever been sent anywhere.") {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                            .font(.title3)
                    }
                }
            }
        }
    }
}
