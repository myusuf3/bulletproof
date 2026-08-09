import AppKit
import SwiftUI

/// Floats a brief success animation over the target app after a replacement:
/// a green highlight on the replaced text when its rect is known, otherwise a
/// small chip near the pointer. Fire-and-forget; never steals focus.
@MainActor final class SuccessFlashController {
    static let shared = SuccessFlashController()
    private var panel: NSPanel?

    func flash(over rect: NSRect) {
        show(FlashHighlightView(), frame: rect.insetBy(dx: -5, dy: -4), lifetime: .milliseconds(1000))
    }

    func flashChip(near point: NSPoint) {
        // Oversized so the chip's shadow and glow aren't clipped by the panel.
        let size = NSSize(width: 190, height: 76)
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = Self.chipFrame(near: point, size: size, in: screen.visibleFrame)
        show(FlashChipView(), frame: frame, lifetime: .milliseconds(1700))
    }

    nonisolated static func chipFrame(near point: NSPoint, size: NSSize, in visibleFrame: NSRect) -> NSRect {
        var origin = NSPoint(x: point.x + 12, y: point.y + 12)
        origin.x = min(max(visibleFrame.minX, origin.x), visibleFrame.maxX - size.width)
        origin.y = min(max(visibleFrame.minY, origin.y), visibleFrame.maxY - size.height)
        return NSRect(origin: origin, size: size)
    }

    private func show(_ view: some View, frame: NSRect, lifetime: Duration) {
        panel?.close()
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: view)
        panel.orderFrontRegardless()
        self.panel = panel
        Task { [weak self] in
            try? await Task.sleep(for: lifetime)
            panel.close()
            if self?.panel === panel { self?.panel = nil }
        }
    }
}

private enum FlashPhase {
    case hidden, shown, fading
}

private struct FlashHighlightView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: FlashPhase = .hidden

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(.green.opacity(0.2))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.green.opacity(0.75), lineWidth: 1.5))
            .shadow(color: .green.opacity(reduceMotion ? 0 : 0.55), radius: 6)
            .scaleEffect(reduceMotion || phase != .hidden ? 1 : 1.04)
            .opacity(phase == .hidden || phase == .fading ? 0 : 1)
            .task {
                withAnimation(.easeOut(duration: 0.15)) { phase = .shown }
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeIn(duration: 0.5)) { phase = .fading }
            }
            .allowsHitTesting(false)
    }
}

private struct FlashChipView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: FlashPhase = .hidden

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white, .green)
                .symbolEffect(.bounce, value: phase == .shown)
            Text("Proofread")
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule().fill(.regularMaterial)
            Capsule().fill(.green.opacity(0.13))
        }
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(colors: [.green.opacity(0.55), .green.opacity(0.18)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            )
        )
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        .shadow(color: .green.opacity(reduceMotion ? 0 : 0.3), radius: 12)
        .scaleEffect(reduceMotion || phase != .hidden ? 1 : 0.7)
        .opacity(phase == .hidden || phase == .fading ? 0 : 1)
        .offset(y: chipOffset)
        .task {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15)
                                       : .spring(duration: 0.35, bounce: 0.45)) {
                phase = .shown
            }
            try? await Task.sleep(for: .milliseconds(1150))
            withAnimation(.easeIn(duration: 0.4)) { phase = .fading }
        }
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chipOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        switch phase {
        case .hidden: return 7
        case .shown: return 0
        case .fading: return -4
        }
    }
}
