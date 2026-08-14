import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, shortcut, accessibility, practice, done
}

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: OnboardingStep = .welcome
    @State private var direction: Edge = .trailing
    @State private var practiceSession = PracticeSession()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                stepContent
                    .id(step)
                    .transition(stepTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 32)

            footer
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .frame(width: 640, height: 480)
        .onAppear { NSApp.activate() }
        .onDisappear { appState.hasSeenOnboarding = true }
        .onExitCommand { OnboardingWindowController.shared.close() }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcome
        case .shortcut: ShortcutStepView()
        case .accessibility: AccessibilityStepView()
        case .practice: PracticeStepView(session: practiceSession)
        case .done: done
        }
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: direction).combined(with: .opacity),
            removal: .move(edge: direction == .trailing ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var footer: some View {
        // Dots overlay the full width so they center on the window,
        // not between the unequal-width Back and Continue buttons.
        ZStack {
            stepDots
            HStack {
                Button("Back") { advance(by: -1) }
                    .opacity(step == .welcome || step == .done ? 0 : 1)
                    .disabled(step == .welcome || step == .done)

                Spacer()

                if step == .done {
                    Button("Start Proofreading") { OnboardingWindowController.shared.close() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { advance(by: 1) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canContinue)
                }
            }
        }
    }

    private var stepDots: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s.rawValue <= step.rawValue ? AnyShapeStyle(Color.accentColor)
                                                      : AnyShapeStyle(.tertiary))
                    .frame(width: 7, height: 7)
            }
        }
        .animation(.spring(duration: 0.3), value: step)
    }

    private var canContinue: Bool {
        switch step {
        case .practice: practiceSession.stage == .success
        default: true
        }
    }

    private func advance(by delta: Int) {
        guard let next = OnboardingStep(rawValue: step.rawValue + delta) else { return }
        direction = delta > 0 ? .trailing : .leading
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15)
                                   : .spring(duration: 0.35, bounce: 0.15)) {
            step = next
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("bulletproof")
                .font(.largeTitle.bold())
            Text("Fix spelling and grammar in any app,\nwithout leaving what you're writing.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("You're all set")
                .font(.title.bold())
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 8)
            recapRow(icon: "keyboard",
                     text: "Select text anywhere and press \(appState.shortcut.displayString) to proofread it in place.")
            recapRow(icon: "cursorarrow.click.2",
                     text: "Right-clicking a selection and choosing Services > Proofread also works.")
            recapRow(icon: "gearshape",
                     text: "Change the shortcut or the proofreading engine anytime in Settings.")
        }
        .frame(maxWidth: 440)
    }

    private func recapRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            Text(text)
        }
    }
}
