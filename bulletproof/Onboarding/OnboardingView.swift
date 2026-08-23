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
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                stepContent
                    .id(step)
                    .transition(stepTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 28)

            footer
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
        }
        .frame(width: 640, height: 540)
        .background(OnboardingBackdrop())
        .onAppear {
            NSApp.activate()
            // Resume where a mid-flow close (or the Accessibility-grant
            // relaunch) left off.
            step = OnboardingStep(rawValue: min(appState.onboarding.resumeStep,
                                                OnboardingStep.done.rawValue)) ?? .welcome
            revealed = true
        }
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
            if step == .welcome {
                // Alone in the ZStack so it centers exactly - a hidden Back
                // button would still reserve space and shove it sideways.
                Button {
                    advance(by: 1)
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(minWidth: 200)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .staggered(5, revealed: revealed, reduceMotion: reduceMotion)
            } else {
                stepDots
                HStack {
                    Button("Back") { advance(by: -1) }
                        .opacity(step == .done ? 0 : 1)
                        .disabled(step == .done)

                    Spacer()

                    if step == .done {
                        Button("Start Proofreading") {
                            UISound.finished()
                            appState.onboarding.complete()
                            OnboardingWindowController.shared.close()
                        }
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
        if delta > 0 {
            UISound.stepForward()
        } else {
            UISound.stepBack()
        }
        appState.onboarding.advance(to: next.rawValue)
        direction = delta > 0 ? .trailing : .leading
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15)
                                   : .spring(duration: 0.35, bounce: 0.15)) {
            step = next
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 108, height: 108)
                .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
                .staggered(0, revealed: revealed, reduceMotion: reduceMotion)

            Text("bulletproof")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.55)],
                                                startPoint: .top, endPoint: .bottom))
                .padding(.top, 8)
                .staggered(1, revealed: revealed, reduceMotion: reduceMotion)

            Text("Fixes spelling and grammar wherever you're writing,\nwithout breaking your flow.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .staggered(2, revealed: revealed, reduceMotion: reduceMotion)

            featureTriptych
                .padding(.top, 26)
                .staggered(3, revealed: revealed, reduceMotion: reduceMotion)

            Text("Everything happens on this Mac. Nothing ever leaves it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 22)
                .staggered(4, revealed: revealed, reduceMotion: reduceMotion)
        }
    }

    private var featureTriptych: some View {
        HStack(spacing: 0) {
            feature(symbol: "keyboard.fill",
                    text: "Press \(appState.shortcut.displayString)\nto fix selected text")
            triptychDivider
            feature(symbol: "wand.and.stars",
                    text: "Works in\nevery app")
            triptychDivider
            feature(symbol: "lock.shield.fill",
                    text: "Private -\nfully on-device")
        }
        // Fixed height: the hairline dividers have no intrinsic size and
        // would otherwise stretch the card to fill the step.
        .frame(height: 96)
        .padding(.vertical, 12)
        .frame(maxWidth: 480)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)))
    }

    private func feature(symbol: String, text: String) -> some View {
        VStack(spacing: 9) {
            featureIcon(symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// Gentle looping life, Alcove-style: each icon stirs on its own offset
    /// period so the card never pulses in lockstep.
    @ViewBuilder
    private func featureIcon(_ symbol: String) -> some View {
        let icon = Image(systemName: symbol)
        if reduceMotion {
            icon
        } else {
            switch symbol {
            case "keyboard.fill":
                icon.symbolEffect(.wiggle, options: .repeat(.periodic(delay: 3.0)))
            case "wand.and.stars":
                icon.symbolEffect(.variableColor.iterative, options: .repeat(.periodic(delay: 3.8)))
            default:
                icon.symbolEffect(.breathe, options: .repeat(.periodic(delay: 4.6)))
            }
        }
    }

    private var triptychDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 4)
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

/// Alcove-style dark glass: a deep neutral gradient with a soft accent glow
/// rising behind the app icon, breathing on a slow loop.
private struct OnboardingBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    /// One hue family throughout: the glow is the accent *darkened* (hue and
    /// saturation kept) rather than thin alpha over gray - alpha compositing
    /// drifts the color into slate and reads as a second, mismatched blue
    /// next to the accent-filled button. The neutrals lean a few percent
    /// toward the accent for the same reason.
    private var glowColor: Color {
        Color.accentColor.mix(with: .black, by: 0.12)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.15).mix(with: .accentColor, by: 0.07),
                                    Color(white: 0.09).mix(with: .accentColor, by: 0.03)],
                           startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(RadialGradient(stops: [
                    .init(color: glowColor.opacity(0.6), location: 0),
                    .init(color: glowColor.opacity(0.28), location: 0.45),
                    .init(color: .clear, location: 1),
                ], center: .center, startRadius: 8, endRadius: 400))
                .frame(width: 800, height: 800)
                .scaleEffect(breathing ? 1.08 : 0.96)
                .opacity(breathing ? 1.0 : 0.75)
                .position(x: 320, y: 120)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.8).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

/// One-shot staggered entrance: fade + settle from 96% + a masking blur,
/// ease-out spring, 80ms apart. Reduced motion renders instantly.
private struct Staggered: ViewModifier {
    let index: Int
    let revealed: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .scaleEffect(revealed ? 1 : 0.96)
            .blur(radius: revealed ? 0 : 6)
            .animation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.12)
                .delay(Double(index) * 0.08), value: revealed)
    }
}

private extension View {
    func staggered(_ index: Int, revealed: Bool, reduceMotion: Bool) -> some View {
        modifier(Staggered(index: index, revealed: revealed, reduceMotion: reduceMotion))
    }
}
