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
                            // The failure revert below re-fires this handler;
                            // when the toggle already matches reality there is
                            // nothing to do (and unregistering a service that
                            // never registered throws a second error).
                            guard wantsEnabled != (SMAppService.mainApp.status == .enabled) else { return }
                            do {
                                if wantsEnabled {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                                launchAtLoginError = nil
                            } catch {
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                                launchAtLoginError = Self.launchAtLoginFailureMessage(
                                    error: error.localizedDescription,
                                    bundlePath: Bundle.main.bundlePath)
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

    /// macOS only registers login items for apps in stable locations;
    /// "Operation not permitted" from a dev build, DMG, or Downloads copy is
    /// that rule, not an actionable error - say so instead of echoing it.
    nonisolated static func launchAtLoginFailureMessage(error: String, bundlePath: String) -> String {
        guard !bundlePath.hasPrefix("/Applications") else { return error }
        return "macOS only allows launch at login for apps installed in /Applications. This copy is running from \(URL(fileURLWithPath: bundlePath).deletingLastPathComponent().path)."
    }
}
