import AppKit
import Observation
import SwiftUI

/// The floating pill at the bottom of the screen while dictating: a live
/// waveform while listening, a spinner while transcribing, a brief message
/// on a hint or failure. Never takes focus - the paste target must stay key.
@MainActor final class DictationOverlayController {
    static let shared = DictationOverlayController()

    @MainActor @Observable
    final class Model {
        var phase: DictationOverlayPhase = .listening
        var levels = AudioLevelHistory()
    }

    /// Roomy and transparent (it ignores the mouse) so a two-line failure
    /// message fits without clipping; the pill hugs its content inside.
    private nonisolated static let size = NSSize(width: 480, height: 100)

    private let model = Model()
    private var panel: NSPanel?
    // Invalidates pending auto-hides when a newer phase supersedes them.
    private var generation = 0

    func show(_ phase: DictationOverlayPhase, levels: AudioLevelHistory) {
        generation += 1
        model.levels = levels
        withAnimation(.spring(duration: 0.3, bounce: 0.2)) { model.phase = phase }
        let panel = panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible {
            panel.setFrame(Self.frame(on: Self.activeScreen()), display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        switch phase {
        case .hint, .failed:
            let expected = generation
            Task {
                try? await Task.sleep(for: .seconds(2.2))
                guard generation == expected else { return }
                hide()
            }
        case .listening, .transcribing:
            break
        }
    }

    func hide() {
        generation += 1
        let expected = generation
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                // A show() during the fade owns the panel now.
                if self.generation == expected { panel.orderOut(nil) }
            }
        }
    }

    /// Bottom-center of the visible frame, clear of the Dock.
    nonisolated static func frame(on visibleFrame: NSRect) -> NSRect {
        NSRect(x: visibleFrame.midX - size.width / 2, y: visibleFrame.minY + 28,
               width: size.width, height: size.height)
    }

    /// The screen the user is working on: wherever the pointer is.
    private static func activeScreen() -> NSRect {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: DictationHUDView(model: model))
        return panel
    }
}

struct DictationHUDView: View {
    let model: DictationOverlayController.Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .frame(minWidth: 150, minHeight: 44)
            .background {
                Capsule().fill(.black.opacity(0.78))
                Capsule().fill(.ultraThinMaterial).opacity(0.35)
            }
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .listening:
            HStack(spacing: 10) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                WaveformView(levels: model.levels.levels, tint: .white)
                    .frame(width: 150, height: 26)
            }
            .accessibilityLabel("Listening")
        case .transcribing:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing…")
            }
        case .hint(let message):
            Label(message, systemImage: "hand.raised.fill")
                .fixedSize()
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 400, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
