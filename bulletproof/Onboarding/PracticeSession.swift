import AppKit
import Observation

nonisolated enum PracticeStage: Equatable {
    case selectAll
    case chord
    case proofreading
    case success
    case failed(String)
}

nonisolated enum PracticeEvent: Equatable {
    case sawSelectAll
    case sawChord
    case proofreadSucceeded
    case proofreadFailed(String)
    case retry
}

nonisolated enum PracticeReducer {
    static func next(_ stage: PracticeStage, _ event: PracticeEvent) -> PracticeStage {
        switch (stage, event) {
        case (.selectAll, .sawSelectAll): .chord
        case (.chord, .sawChord): .proofreading
        // Pressing the shortcut before ⌘A still counts - don't punish users
        // who selected with the mouse.
        case (.selectAll, .sawChord): .proofreading
        case (.proofreading, .proofreadSucceeded): .success
        case (.proofreading, .proofreadFailed(let message)): .failed(message)
        case (.failed, .retry): .chord
        default: stage
        }
    }
}

@MainActor @Observable final class PracticeSession {
    var stage: PracticeStage = .selectAll
    var text = "Its a beutiful day and the whether is grate. I cant wait too go outside and enjoi the sunshine with my freinds."
    var pressedModifiers: NSEvent.ModifierFlags = []

    func handle(_ event: PracticeEvent) {
        stage = PracticeReducer.next(stage, event)
    }

    /// Wired into HotkeyDispatcher.practiceHandler while the practice step is
    /// visible. Reads the editor text directly - no CGEvents - so practice
    /// works even when Accessibility was denied. Presses in other stages are
    /// inert (the dispatcher already never falls through to the real flow).
    @discardableResult
    func hotkeyFired(engine: any ProofreadingEngine) -> Task<Void, Never>? {
        guard stage == .selectAll || stage == .chord else { return nil }
        handle(.sawChord)
        let input = text
        return Task {
            do {
                let corrected = try await engine.proofread(input)
                text = corrected
                handle(.proofreadSucceeded)
            } catch {
                handle(.proofreadFailed(error.localizedDescription))
            }
        }
    }
}
