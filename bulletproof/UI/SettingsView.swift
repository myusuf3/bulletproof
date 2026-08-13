import SwiftUI

nonisolated enum SettingsPane: String, CaseIterable, Identifiable {
    case general, shortcut, engine, models, about

    nonisolated var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .shortcut: "Shortcut"
        case .engine: "Engine"
        case .models: "Models"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .shortcut: "command"
        case .engine: "brain.fill"
        case .models: "arrow.down.circle.fill"
        case .about: "info"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: .gray
        case .shortcut: .blue
        case .engine: .purple
        case .models: .green
        case .about: .indigo
        }
    }

    /// What users type when hunting for a setting, beyond the pane title.
    var keywords: [String] {
        switch self {
        case .general: ["launch", "login", "startup", "onboarding", "walkthrough", "counter"]
        case .shortcut: ["hotkey", "keyboard", "record", "permission", "accessibility", "notifications"]
        case .engine: ["apple intelligence", "proofreading", "local", "on-device"]
        case .models: ["download", "gemma", "qwen", "disk", "delete", "storage"]
        case .about: ["version", "update", "sparkle", "github", "release"]
        }
    }

    static func matching(_ query: String) -> [SettingsPane] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return allCases }
        return allCases.filter { pane in
            pane.title.lowercased().contains(trimmed)
                || pane.keywords.contains { $0.contains(trimmed) }
        }
    }
}

struct SettingsView: View {
    @State private var selection: SettingsPane?
    @State private var query = ""

    init(initialSelection: SettingsPane = .general) {
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search Settings", text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternarySystemFill)))
                .padding(.horizontal, 10)

                List(selection: $selection) {
                    let visible = SettingsPane.matching(query)
                    Section("General") {
                        ForEach([SettingsPane.general, .shortcut].filter(visible.contains)) { pane in
                            PaneRow(pane: pane)
                        }
                    }
                    Section("Proofreading") {
                        ForEach([SettingsPane.engine, .models].filter(visible.contains)) { pane in
                            PaneRow(pane: pane)
                        }
                    }
                    Section {
                        if visible.contains(.about) {
                            PaneRow(pane: .about)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(selection?.title ?? "")
                        .font(.title2.bold())
                        .padding(.bottom, 10)
                    detailPane
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 20)
                .frame(maxWidth: 680, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selection ?? .general {
        case .general: GeneralSettingsView()
        case .shortcut: ShortcutSettingsPane()
        case .engine: EngineSettingsView()
        case .models: ModelsSettingsView()
        case .about: AboutSettingsView()
        }
    }
}

private struct PaneRow: View {
    let pane: SettingsPane

    var body: some View {
        Label {
            Text(pane.title)
        } icon: {
            RoundedRectangle(cornerRadius: 6)
                .fill(pane.iconColor.gradient)
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: pane.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
        .tag(pane)
    }
}

/// Shared row layout: label with optional description, trailing control.
struct SettingRow<Control: View>: View {
    let title: String
    var description: String? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let description {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}

/// Grouped card wrapping a stack of SettingRows, System Settings style.
struct SettingsCard<Content: View>: View {
    var header: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header)
                    .font(.headline)
                    .padding(.top, 14)
            }
            VStack(spacing: 0) {
                content()
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .quaternarySystemFill)))
        }
        .padding(.bottom, 8)
    }
}

/// Thin separator for use between rows inside a SettingsCard.
struct SettingDivider: View {
    var body: some View {
        Divider().padding(.leading, 14)
    }
}
