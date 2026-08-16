import AppIntents

/// Exposes proofreading to Shortcuts, Spotlight, and Siri.
struct ProofreadTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Proofread Text"
    static let description = IntentDescription(
        "Corrects spelling, grammar, and punctuation with on-device intelligence. Text never leaves this Mac."
    )

    @Parameter(title: "Text")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Proofread \(\.$text)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProofreadingError.emptyInput
        }
        let engine = await AppState.shared.makeEngine()
        let engineLabel = await AppState.shared.engineChoice.telemetryLabel
        let start = ContinuousClock.now
        func record(_ outcome: ProofreadOutcome, outputChars: Int? = nil) {
            ProofreadTelemetry.shared.record(ProofreadEvent(
                entryPoint: .intent, engine: engineLabel,
                inputChars: text.count, outputChars: outputChars,
                outcome: outcome, phases: [],
                totalMs: (ContinuousClock.now - start) / .milliseconds(1)))
        }
        do {
            let corrected = try await engine.proofread(text)
            record(corrected == text ? .unchanged : .applied, outputChars: corrected.count)
            return .result(value: corrected)
        } catch {
            record(.from(error))
            throw error
        }
    }
}

struct BulletproofShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ProofreadTextIntent(),
            phrases: [
                "Proofread text with \(.applicationName)",
                "Fix grammar with \(.applicationName)",
            ],
            shortTitle: "Proofread Text",
            systemImageName: "checkmark.seal"
        )
    }
}
