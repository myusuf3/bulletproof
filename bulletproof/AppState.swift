import Foundation
import FoundationModels
import Observation

nonisolated enum EngineChoice: Codable, Hashable {
    case appleIntelligence
    case local(modelID: String)
}

@MainActor @Observable
final class AppState {
    static let shared = AppState()

    private static let engineChoiceKey = "engineChoice"
    private static let shortcutKey = "proofreadShortcut"
    private static let verifyCorrectionsKey = "verifyCorrections"

    var engineChoice: EngineChoice {
        didSet {
            if let data = try? JSONEncoder().encode(engineChoice) {
                UserDefaults.standard.set(data, forKey: Self.engineChoiceKey)
            }
            // Switching engines frees the ~3 GB resident model immediately
            // instead of waiting out the idle timer.
            let keep: URL? = if case .local(let id) = engineChoice { store.directory(for: id) } else { nil }
            Task { await LocalModelRuntime.shared.retainOnly(keep) }
        }
    }

    var shortcut: KeyCombo {
        didSet {
            if let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(data, forKey: Self.shortcutKey)
            }
            HotkeyDispatcher.shared.registerOrNotify(shortcut)
        }
    }

    /// Experimental scored gate (default off until tuned): double-check
    /// every correction with the local model before pasting.
    var verifyCorrectionsEnabled: Bool {
        didSet { UserDefaults.standard.set(verifyCorrectionsEnabled, forKey: Self.verifyCorrectionsKey) }
    }

    let onboarding = OnboardingProgress()
    let store: ModelStore
    let downloads: ModelDownloadManager
    let activity = MenuBarActivity()
    let history = CorrectionHistory()

    init(store: ModelStore = ModelStore()) {
        self.store = store
        self.downloads = ModelDownloadManager(store: store)
        if let data = UserDefaults.standard.data(forKey: Self.engineChoiceKey),
           let saved = try? JSONDecoder().decode(EngineChoice.self, from: data) {
            engineChoice = saved
        } else {
            engineChoice = .appleIntelligence
        }
        if let data = UserDefaults.standard.data(forKey: Self.shortcutKey),
           let saved = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            shortcut = saved
        } else {
            shortcut = .default
        }
        verifyCorrectionsEnabled = UserDefaults.standard.bool(forKey: Self.verifyCorrectionsKey)
        store.cleanupPartials()
    }

    /// The single seam the service provider and UI use to get an engine.
    func makeEngine() -> any ProofreadingEngine {
        #if DEBUG
        // CI runners have no Apple Intelligence; end-to-end tests exercise the
        // services pipeline against a deterministic engine instead.
        if ProcessInfo.processInfo.environment["BULLETPROOF_FAKE_ENGINE"] == "1" {
            return UppercasingFakeEngine()
        }
        #endif
        // Gate inside the recorder so history only ever holds accepted output.
        switch engineChoice {
        case .appleIntelligence:
            return RecordingEngine(wrapped: scoredIfEnabled(
                OutputGatedEngine(wrapped: AppleIntelligenceEngine())))
        case .local(let modelID):
            return RecordingEngine(wrapped: scoredIfEnabled(
                OutputGatedEngine(wrapped: LocalModelEngine(modelDirectory: store.directory(for: modelID))),
                preferredModelID: modelID))
        }
    }

    /// The scorer is the resident local model - it also judges Apple
    /// Intelligence output (scorer and generator need not match). Without an
    /// installed model the gate silently stays out of the chain.
    private func scoredIfEnabled(_ engine: any ProofreadingEngine,
                                 preferredModelID: String? = nil) -> any ProofreadingEngine {
        guard verifyCorrectionsEnabled,
              let modelID = preferredModelID ?? store.installedModelIDs().sorted().first else {
            return engine
        }
        return ScoredGateEngine(wrapped: engine,
                                scorer: MLXSpanScorer(modelDirectory: store.directory(for: modelID)))
    }

    /// Fallback happens first so makeEngine() can never hand out an engine
    /// pointing at a directory this method is about to remove.
    func deleteAllModels() {
        if case .local = engineChoice {
            engineChoice = .appleIntelligence
        } else {
            Task { await LocalModelRuntime.shared.evictNow() }
        }
        for id in store.installedModelIDs() {
            downloads.delete(id: id)
        }
    }

    /// Nil when Apple Intelligence is ready; otherwise an actionable reason.
    var appleIntelligenceIssue: String? {
        switch AppleIntelligenceEngine.model.availability {
        case .available:
            nil
        case .unavailable(let reason):
            AppleIntelligenceEngine.explanation(for: reason)
        }
    }
}

#if DEBUG
nonisolated struct UppercasingFakeEngine: ProofreadingEngine {
    func proofread(_ text: String) async throws -> String {
        text.uppercased()
    }
}
#endif
