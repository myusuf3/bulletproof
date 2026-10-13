import Foundation
import FoundationModels
import Observation

nonisolated enum EngineChoice: Codable, Hashable {
    case appleIntelligence
    case local(modelID: String)
}

@MainActor @Observable
final class AppState {
    /// Tests run inside bulletproof.app, which shares the bundle ID (and so
    /// the preferences) of the copy in /Applications. Under the test host the
    /// shared state gets a scratch domain, so no test can rewrite the user's
    /// real engine, speech model, or dictation settings.
    static let shared = AppState(defaults: AppDelegate.isTestHost(environment: ProcessInfo.processInfo.environment)
        ? scratchDefaults() : .standard)

    nonisolated static let testDefaultsSuite = "com.mahdiyusuf.bulletproof.tests"

    private static func scratchDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: testDefaultsSuite)!
        defaults.removePersistentDomain(forName: testDefaultsSuite)
        return defaults
    }

    private static let engineChoiceKey = "engineChoice"
    private static let shortcutKey = "proofreadShortcut"
    private static let verifyCorrectionsKey = "verifyCorrections"
    private static let fixSoundKey = "playSoundOnFix"
    private static let dictationShortcutKey = "dictationShortcut"
    private static let speechModelKey = "speechModel"
    private static let microphoneKey = "microphoneUID"
    private static let proofreadDictationKey = "proofreadDictation"
    private static let dictationEngineChoiceKey = "dictationEngineChoice"

    var engineChoice: EngineChoice {
        didSet {
            if let data = try? JSONEncoder().encode(engineChoice) {
                defaults.set(data, forKey: Self.engineChoiceKey)
            }
            releaseUnusedModels()
        }
    }

    var shortcut: KeyCombo {
        didSet {
            if let data = try? JSONEncoder().encode(shortcut) {
                defaults.set(data, forKey: Self.shortcutKey)
            }
            HotkeyDispatcher.shared.registerOrNotify(shortcut)
        }
    }

    /// Experimental scored gate (default off until tuned): double-check
    /// every correction with the local model before pasting.
    var verifyCorrectionsEnabled: Bool {
        didSet { defaults.set(verifyCorrectionsEnabled, forKey: Self.verifyCorrectionsKey) }
    }

    /// Subtle tick when a correction lands in place. Default on.
    var playSoundOnFix: Bool {
        didSet { defaults.set(playSoundOnFix, forKey: Self.fixSoundKey) }
    }

    var dictationShortcut: KeyCombo {
        didSet {
            if let data = try? JSONEncoder().encode(dictationShortcut) {
                defaults.set(data, forKey: Self.dictationShortcutKey)
            }
            HotkeyDispatcher.shared.registerOrNotify(dictationShortcut, for: .dictation)
        }
    }

    var speechModel: SpeechModelChoice {
        didSet { defaults.set(speechModel.rawValue, forKey: Self.speechModelKey) }
    }

    /// CoreAudio UID of the chosen input; nil follows the system default.
    var microphoneUID: String? {
        didSet { defaults.set(microphoneUID, forKey: Self.microphoneKey) }
    }

    /// Run dictated text through the proofreading engine before inserting.
    var proofreadDictation: Bool {
        didSet {
            defaults.set(proofreadDictation, forKey: Self.proofreadDictationKey)
            releaseUnusedModels()
        }
    }

    /// The engine that proofreads dictation; nil follows engineChoice. Lets
    /// dictation run the fast local fine-tune while typed text stays on
    /// another engine.
    var dictationEngineChoice: EngineChoice? {
        didSet {
            if let dictationEngineChoice, let data = try? JSONEncoder().encode(dictationEngineChoice) {
                defaults.set(data, forKey: Self.dictationEngineChoiceKey)
            } else {
                defaults.removeObject(forKey: Self.dictationEngineChoiceKey)
            }
            releaseUnusedModels()
        }
    }

    /// The engine dictation actually runs.
    var effectiveDictationEngine: EngineChoice {
        Self.dictationEngine(choice: dictationEngineChoice, proofreading: engineChoice,
                             installed: store.installedModelIDs())
    }

    /// Dictation's own pick while it's usable; a local model whose files are
    /// gone falls back to the proofreading engine rather than failing every
    /// dictation into the raw transcript.
    nonisolated static func dictationEngine(choice: EngineChoice?, proofreading: EngineChoice,
                                            installed: [String]) -> EngineChoice {
        switch choice {
        case nil: proofreading
        case .appleIntelligence: .appleIntelligence
        case .local(let id): installed.contains(id) ? .local(modelID: id) : proofreading
        }
    }

    /// Switching engines frees the ~3 GB resident model immediately instead
    /// of waiting out the idle timer - unless the other feature still runs it.
    private func releaseUnusedModels() {
        let inUse = Self.localModelsInUse(proofreading: engineChoice,
                                          dictation: proofreadDictation ? effectiveDictationEngine : nil)
        let keep = Set(inUse.map(store.directory(for:)))
        Task { await LocalModelRuntime.shared.retainOnly(keep) }
    }

    /// dictation is nil while dictation skips proofreading.
    nonisolated static func localModelsInUse(proofreading: EngineChoice, dictation: EngineChoice?) -> Set<String> {
        var ids: Set<String> = []
        for case .local(let id) in [proofreading, dictation] { ids.insert(id) }
        return ids
    }

    let onboarding: OnboardingProgress
    let store: ModelStore
    let downloads: ModelDownloadManager
    let activity = MenuBarActivity()
    let history: CorrectionHistory
    private let defaults: UserDefaults

    init(store: ModelStore = ModelStore(), defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.onboarding = OnboardingProgress(defaults: defaults)
        self.history = CorrectionHistory(defaults: defaults)
        self.store = store
        self.downloads = ModelDownloadManager(store: store)
        if let data = defaults.data(forKey: Self.engineChoiceKey),
           let saved = try? JSONDecoder().decode(EngineChoice.self, from: data) {
            engineChoice = saved
        } else {
            engineChoice = Self.defaultEngineChoice(installed: store.installedModelIDs())
        }
        if let data = defaults.data(forKey: Self.shortcutKey),
           let saved = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            shortcut = saved
        } else {
            shortcut = .default
        }
        if let data = defaults.data(forKey: Self.dictationShortcutKey),
           let saved = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            dictationShortcut = saved
        } else {
            dictationShortcut = .dictationDefault
        }
        speechModel = defaults.string(forKey: Self.speechModelKey)
            .flatMap(SpeechModelChoice.init(rawValue:)) ?? .appleSpeech
        microphoneUID = defaults.string(forKey: Self.microphoneKey)
        proofreadDictation = defaults.bool(forKey: Self.proofreadDictationKey)
        dictationEngineChoice = defaults.data(forKey: Self.dictationEngineChoiceKey)
            .flatMap { try? JSONDecoder().decode(EngineChoice.self, from: $0) }
        verifyCorrectionsEnabled = defaults.bool(forKey: Self.verifyCorrectionsKey)
        playSoundOnFix = defaults.object(forKey: Self.fixSoundKey) as? Bool ?? true
        store.cleanupPartials()
        downloads.onInstalled = { [weak self] id in self?.adoptRecommendedModelIfUnchosen(id) }
    }

    /// With no saved choice: the app's fine-tune when it's installed, otherwise
    /// Apple Intelligence (which needs no download).
    nonisolated static func defaultEngineChoice(installed: [String]) -> EngineChoice {
        installed.contains(ModelCatalog.recommendedProofreaderID)
            ? .local(modelID: ModelCatalog.recommendedProofreaderID) : .appleIntelligence
    }

    /// Downloading the recommended model switches to it unless the user has
    /// ever picked an engine themselves (an explicit choice is never overridden).
    nonisolated static func shouldAdopt(installedID: String, hasSavedChoice: Bool) -> Bool {
        installedID == ModelCatalog.recommendedProofreaderID && !hasSavedChoice
    }

    private func adoptRecommendedModelIfUnchosen(_ id: String) {
        let saved = defaults.data(forKey: Self.engineChoiceKey) != nil
        if Self.shouldAdopt(installedID: id, hasSavedChoice: saved) {
            engineChoice = .local(modelID: id)
        }
    }

    /// The single seam the service provider and UI use to get an engine.
    /// recordsStats is false only for the onboarding practice run, whose
    /// canned typos must not become drill material. Dictation passes
    /// ProofreadPrompt.dictationInstructions and its own engine choice.
    func makeEngine(choice: EngineChoice? = nil,
                    recordsStats: Bool = true,
                    instructions: String = ProofreadPrompt.instructions) -> any ProofreadingEngine {
        #if DEBUG
        // CI runners have no Apple Intelligence; end-to-end tests exercise the
        // services pipeline against a deterministic engine instead.
        if ProcessInfo.processInfo.environment["BULLETPROOF_FAKE_ENGINE"] == "1" {
            return UppercasingFakeEngine()
        }
        #endif
        // Gate inside the recorder so history only ever holds accepted output.
        switch choice ?? engineChoice {
        case .appleIntelligence:
            return RecordingEngine(wrapped: scoredIfEnabled(
                OutputGatedEngine(wrapped: AppleIntelligenceEngine(instructions: instructions))),
                recordsStats: recordsStats)
        case .local(let modelID):
            return RecordingEngine(wrapped: scoredIfEnabled(
                OutputGatedEngine(wrapped: LocalModelEngine(modelDirectory: store.directory(for: modelID),
                                                           instructions: instructions)),
                preferredModelID: modelID),
                recordsStats: recordsStats)
        }
    }

    func makeSpeechEngine() -> any SpeechToTextEngine {
        switch speechModel {
        case .appleSpeech:
            AppleSpeechEngine()
        case .whistle:
            WhistleSpeechEngine(modelFile: whistleModelFile)
        }
    }

    var whistleModelFile: URL {
        store.directory(for: ModelCatalog.whistle.id).appendingPathComponent(ModelCatalog.whistleModelFile)
    }

    /// The scorer is the resident local model - it also judges Apple
    /// Intelligence output (scorer and generator need not match). Without an
    /// installed model the gate silently stays out of the chain.
    private func scoredIfEnabled(_ engine: any ProofreadingEngine,
                                 preferredModelID: String? = nil) -> any ProofreadingEngine {
        guard verifyCorrectionsEnabled,
              let modelID = preferredModelID
                ?? ModelCatalog.proofreadingIDs(installed: store.installedModelIDs()).sorted().first else {
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
        if case .local = dictationEngineChoice { dictationEngineChoice = nil }
        speechModel = .appleSpeech
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
