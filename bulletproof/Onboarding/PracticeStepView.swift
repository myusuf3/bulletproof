import SwiftUI
import Carbon.HIToolbox

struct PracticeStepView: View {
    @Bindable var session: PracticeSession
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 18) {
            Text("Try it")
                .font(.title.bold())

            editor
                .frame(height: 110)

            ZStack {
                keycapArea
                    .id(showsSelectAllRow)
                    .transition(reduceMotion
                        ? .opacity
                        : .push(from: .bottom).combined(with: .opacity))
            }
            .animation(.spring(duration: 0.3), value: showsSelectAllRow)

            statusLine
        }
        .onAppear {
            installMonitor()
            HotkeyDispatcher.shared.practiceHandler = { session.hotkeyFired(engine: appState.makeEngine()) }
        }
        .onDisappear {
            removeMonitor()
            HotkeyDispatcher.shared.practiceHandler = nil
        }
    }

    private var isSuccess: Bool { session.stage == .success }
    private var isProofreading: Bool { session.stage == .proofreading }
    private var showsSelectAllRow: Bool { session.stage == .selectAll }

    @ViewBuilder
    private var editor: some View {
        Group {
            if isSuccess {
                Text(session.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
                    .transition(.opacity)
            } else {
                TextEditor(text: $session.text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .disabled(isProofreading)
            }
        }
        .font(.body)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
            isSuccess ? Color.green.opacity(0.6) : Color(nsColor: .separatorColor)))
        .overlay {
            if isProofreading && !reduceMotion {
                ShimmerOverlay()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isSuccess)
    }

    @ViewBuilder
    private var keycapArea: some View {
        if showsSelectAllRow {
            KeycapRow(combo: KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: .command),
                      pressedModifiers: session.pressedModifiers)
        } else {
            KeycapRow(combo: appState.shortcut,
                      pressedModifiers: isProofreading || isSuccess ? [] : session.pressedModifiers,
                      isSuccess: isProofreading || isSuccess)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch session.stage {
        case .selectAll:
            caption("Click in the text, then press ⌘A to select everything.")
        case .chord:
            caption("Now press \(appState.shortcut.displayString) to proofread it.")
        case .proofreading:
            HStack(spacing: 8) {
                if reduceMotion { ProgressView().controlSize(.small) }
                caption("Proofreading…")
            }
        case .success:
            Label {
                Text("You did it.")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .font(.title3.weight(.medium))
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        case .failed(let message):
            VStack(spacing: 6) {
                caption(message).foregroundStyle(.red)
                Button("Try Again") { session.handle(.retry) }
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            switch event.type {
            case .flagsChanged:
                session.pressedModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            case .keyDown:
                if event.keyCode == UInt16(kVK_ANSI_A),
                   event.modifierFlags.contains(.command) {
                    session.handle(.sawSelectAll)
                }
            default:
                break
            }
            // Always pass events through so ⌘A actually selects the text.
            return event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        session.pressedModifiers = []
    }
}

/// A soft highlight band sweeping across the text while the model works.
/// Accent-tinted with normal blending so it reads on both light and dark
/// backgrounds (a white additive band disappears on a light text field).
private struct ShimmerOverlay: View {
    @State private var phase: CGFloat = -0.6

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.accentColor.opacity(0.22), location: 0.5),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.6)
            .offset(x: phase * geo.size.width)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
        }
        .allowsHitTesting(false)
    }
}
