import AppKit
import SwiftUI
import Testing
@testable import bulletproof

/// Renders the settings window to PNGs so layout can be reviewed without
/// launching the app. Files land in /tmp/bulletproof-snapshots/.
/// Local-only: rendering hogs the main actor and starves parallel
/// main-actor tests on slow CI runners (and nobody reads the PNGs there).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
@MainActor
struct SettingsSnapshotTests {
    private static let outputDir = URL(fileURLWithPath: "/tmp/bulletproof-snapshots")

    private func write(_ png: Data, _ name: String) throws {
        try FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)
        try png.write(to: Self.outputDir.appendingPathComponent("\(name).png"))
    }

    /// Full-window snapshot: NavigationSplitView needs a real, frontmost
    /// window and several runloop turns before SwiftUI commits a frame.
    private func snapshotWindow<V: View>(_ view: V, size: NSSize, name: String) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.makeKeyAndOrderFront(nil)
        for _ in 0..<10 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
        guard let contentView = window.contentView,
              let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            Issue.record("could not create bitmap for \(name)")
            return
        }
        contentView.cacheDisplay(in: contentView.bounds, to: rep)
        window.orderOut(nil)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("could not encode png for \(name)")
            return
        }
        try write(png, name)
    }

    /// Pane-content snapshot via ImageRenderer - no window needed, reliable
    /// for everything except NavigationSplitView chrome.
    private func snapshotPane<V: View>(_ view: V, width: CGFloat, name: String) throws {
        let renderer = ImageRenderer(content: view
            .frame(width: width)
            .background(Color(nsColor: .windowBackgroundColor)))
        renderer.scale = 2
        guard let tiff = renderer.nsImage?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("could not render \(name)")
            return
        }
        try write(png, name)
    }

    @Test func renderSettingsWindow() throws {
        try snapshotWindow(SettingsView().environment(AppState.shared),
                           size: NSSize(width: 940, height: 620), name: "settings-window")
    }

    @Test func renderPaneContents() throws {
        try snapshotPane(GeneralSettingsView().environment(AppState.shared), width: 660, name: "pane-general")
        try snapshotPane(ShortcutSettingsPane().environment(AppState.shared), width: 660, name: "pane-shortcut")
        try snapshotPane(EngineSettingsView().environment(AppState.shared), width: 660, name: "pane-engine")
        try snapshotPane(ModelsSettingsView().environment(AppState.shared), width: 660, name: "pane-models")
        try snapshotPane(AppsSettingsView().environment(AppState.shared), width: 660, name: "pane-apps")
        try snapshotPane(StatisticsSettingsView().environment(AppState.shared), width: 660, name: "pane-statistics")
        try snapshotPane(AboutSettingsView().environment(AppState.shared), width: 660, name: "pane-about")
    }
}
