import SwiftUI

struct AboutSettingsView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("bulletproof")
                            .font(.title3.bold())
                        Text("Version \(version) (\(build))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check for Updates…") {
                        UpdaterController.shared.checkForUpdates()
                    }
                }
                .padding(14)
            }

            SettingsCard(header: "Links") {
                SettingRow(title: "Source code",
                           description: "bulletproof is developed in the open.") {
                    Button("GitHub") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/myusuf3/bulletproof")!)
                    }
                }
                SettingDivider()
                SettingRow(title: "Release notes",
                           description: "What changed in each version.") {
                    Button("View Releases") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/myusuf3/bulletproof/releases")!)
                    }
                }
            }

            SettingsCard(header: "Privacy") {
                SettingRow(title: "Everything stays on this Mac",
                           description: "Text is proofread by Apple Intelligence or a downloaded local model. The only network traffic is downloading models you request and checking for updates.") {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
            }
        }
    }
}
