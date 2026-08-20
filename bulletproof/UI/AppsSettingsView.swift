import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One toggle per app. For ordinary apps it means "proofread here" (on by
/// default); for known terminals it means "allow despite being a terminal"
/// (off by default). Secure fields are never overridable, in any app.
struct AppsSettingsView: View {
    @State private var rows: [AppRow] = []

    struct AppRow: Identifiable {
        let id: String
        let name: String
        let isTerminal: Bool
        var enabled: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard {
                SettingRow(title: "Per-app control",
                           description: "Running apps appear automatically. Turning an app off refuses the shortcut there; terminals are off unless you allow them.") {
                    Button("Add App…") { addApp() }
                }
            }

            SettingsCard(header: "Apps") {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        SettingDivider()
                    }
                    SettingRow(title: row.name,
                               description: row.isTerminal
                                   ? "Terminal - proofreading a selected command can change what it runs."
                                   : row.id) {
                        Toggle("", isOn: binding(for: row))
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }
        }
        .onAppear(perform: refresh)
    }

    private func binding(for row: AppRow) -> Binding<Bool> {
        Binding(
            get: { row.enabled },
            set: { enabled in
                var policy = AppPolicyStore.shared.policy(for: row.id)
                if row.isTerminal {
                    policy.allowDespiteTerminal = enabled
                } else {
                    policy.proofreadingDisabled = !enabled
                }
                AppPolicyStore.shared.setPolicy(policy, for: row.id, displayName: row.name)
                refresh()
            })
    }

    private func refresh() {
        let store = AppPolicyStore.shared
        var byID: [String: AppRow] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { continue }
            byID[id] = row(id: id, name: app.localizedName ?? id, store: store)
        }
        // Apps added manually or configured earlier keep their rows while
        // not running.
        for id in Set(store.policies.keys).union(store.displayNames.keys) where byID[id] == nil {
            byID[id] = row(id: id, name: store.displayNames[id] ?? id, store: store)
        }
        rows = byID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func row(id: String, name: String, store: AppPolicyStore) -> AppRow {
        let policy = store.policy(for: id)
        let isTerminal = FocusGuard.isKnownTerminal(bundleID: id)
        return AppRow(id: id, name: name, isTerminal: isTerminal,
                      enabled: isTerminal ? policy.allowDespiteTerminal : !policy.proofreadingDisabled)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else {
            return
        }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        // Registering the display name creates the row; the policy stays
        // default until the user flips the toggle.
        AppPolicyStore.shared.setPolicy(AppPolicyStore.shared.policy(for: id),
                                        for: id, displayName: name)
        refresh()
    }
}
