import AppKit
import SwiftUI

/// Monkeytype-inspired palette: charcoal room, dim resting text, one warm
/// yellow accent. Deliberately its own look - the drill is a focused little
/// game, not another settings pane.
private enum DrillTheme {
    static let background = Color(red: 0.173, green: 0.180, blue: 0.192)
    static let dim = Color(red: 0.42, green: 0.43, blue: 0.45)
    static let bright = Color(red: 0.85, green: 0.85, blue: 0.86)
    static let yellow = Color(red: 0.886, green: 0.718, blue: 0.078)
    static let red = Color(red: 0.79, green: 0.36, blue: 0.33)
}

struct PracticeDrillView: View {
    @State private var session: DrillSession
    @FocusState private var typingFocused: Bool
    @State private var finished = false

    init(words: [DrillWord]) {
        _session = State(initialValue: DrillSession(words: words))
    }

    var body: some View {
        VStack(spacing: 0) {
            if finished {
                summary
            } else {
                drill
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DrillTheme.background)
        .onExitCommand { PracticeDrillWindowController.shared.close() }
    }

    private var drill: some View {
        VStack(spacing: 28) {
            Spacer()

            Label("fix your most-corrected words", systemImage: "keyboard")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(DrillTheme.dim)

            wordStream
                .font(.system(size: 26, design: .monospaced))
                .lineSpacing(12)
                .frame(maxWidth: 780, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            TextField("", text: Binding(
                get: { session.typed },
                set: { session.typed = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 24, design: .monospaced))
                .foregroundStyle(DrillTheme.bright)
                .tint(DrillTheme.yellow)
                .multilineTextAlignment(.center)
                .frame(width: 320)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
                .focused($typingFocused)
                .onSubmit { submit() }
                // Space-submit must not run inside the binding's setter: the
                // reentrant typed = "" never reaches the field editor, so the
                // previous answer stays in the field and prefixes the next one.
                .onChange(of: session.typed) { _, newValue in
                    if newValue.hasSuffix(" ") {
                        submit()
                    }
                }

            Text("type the correction · space or return submits · esc quits")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(DrillTheme.dim.opacity(0.7))

            Spacer()
        }
        .onAppear {
            DispatchQueue.main.async { typingFocused = true }
        }
    }

    /// One flowing Text so wrapping stays native; per-word color carries the
    /// state, a yellow bar marks the caret word.
    private var wordStream: Text {
        var stream = Text(verbatim: "")
        for (index, word) in session.words.enumerated() {
            if index > 0 {
                stream = stream + Text(verbatim: "  ")
            }
            switch session.state(at: index) {
            case .pending:
                stream = stream + Text(word.typo).foregroundColor(DrillTheme.dim)
            case .current:
                stream = stream + Text(verbatim: "|").foregroundColor(DrillTheme.yellow)
                    + Text(word.typo).foregroundColor(DrillTheme.bright)
            case .correct:
                stream = stream + Text(word.fix).foregroundColor(DrillTheme.bright.opacity(0.55))
            case .missed:
                stream = stream + Text(word.typo).foregroundColor(DrillTheme.red)
            }
        }
        return stream
    }

    private func submit() {
        session.submitCurrent()
        if session.isFinished {
            PracticeSchedule.shared.completeToday()
            UISound.practiceSuccess()
            withAnimation(.easeOut(duration: 0.25)) { finished = true }
        }
    }

    private var summary: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("\(session.correctCount)/\(session.words.count)")
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .foregroundStyle(DrillTheme.yellow)
            Text("fixed")
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(DrillTheme.dim)

            if !session.missedWords.isEmpty {
                VStack(spacing: 6) {
                    ForEach(session.missedWords, id: \.typo) { word in
                        Text("\(word.typo) -> \(word.fix)")
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundStyle(DrillTheme.red)
                    }
                }
                .padding(.top, 10)
            }

            Text("streak: \(PracticeSchedule.shared.streak) day\(PracticeSchedule.shared.streak == 1 ? "" : "s") · come back tomorrow")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(DrillTheme.dim)
                .padding(.top, 8)

            Button("Done") { PracticeDrillWindowController.shared.close() }
                .buttonStyle(.borderedProminent)
                .tint(DrillTheme.yellow)
                .foregroundStyle(.black)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 12)
            Spacer()
        }
    }
}

@MainActor final class PracticeDrillWindowController {
    static let shared = PracticeDrillWindowController()
    private var window: NSWindow?
    private var onClose: (() -> Void)?

    func show(words: [DrillWord], onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        NSApp.activate()
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: PracticeDrillView(words: words))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Practice"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(buttonType)?.isHidden = true
        }
        window.setContentSize(NSSize(width: 900, height: 540))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let controller = PracticeDrillWindowController.shared
                controller.window = nil
                controller.onClose?()
                controller.onClose = nil
            }
        }
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}
