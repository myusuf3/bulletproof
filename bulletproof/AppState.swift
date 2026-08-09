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
    static let onboardingKey = "hasSeenOnboarding"

    var engineChoice: EngineChoice {
        didSet {
            if let data = try? JSONEncoder().encode(engineChoice) {
                UserDefaults.standard.set(data, forKey: Self.engineChoiceKey)
            }
        }
    }

    var shortcut: KeyCombo {
        didSet {
            if let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(data, forKey: Self.shortcutKey)
            }
            HotkeyDispatcher.shared.register(shortcut)
        }
    }

    var hasSeenOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasSeenOnboarding, forKey: Self.onboardingKey) }
    }

    let store: ModelStore
    let downloads: ModelDownloadManager

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
        hasSeenOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
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
        switch engineChoice {
        case .appleIntelligence:
            return AppleIntelligenceEngine()
        case .local(let modelID):
            return LocalModelEngine(modelDirectory: store.directory(for: modelID))
        }
    }

    /// Nil when Apple Intelligence is ready; otherwise an actionable reason.
    var appleIntelligenceIssue: String? {
        switch SystemLanguageModel.default.availability {
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
