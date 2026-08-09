import Foundation
import Testing
@testable import bulletproof

private final class CountingEngine: ProofreadingEngine, @unchecked Sendable {
    private(set) var calls = 0

    func proofread(_ text: String) async throws -> String {
        calls += 1
        return "corrected"
    }
}

@MainActor
struct PracticeSessionTests {
    @Test func chordDuringChordStageProofreads() async {
        let session = PracticeSession()
        let engine = CountingEngine()
        session.handle(.sawSelectAll)
        let task = session.hotkeyFired(engine: engine)
        #expect(session.stage == .proofreading)
        await task?.value
        #expect(session.stage == .success)
        #expect(session.text == "corrected")
        #expect(engine.calls == 1)
    }

    @Test func chordBeforeSelectAllStillProofreads() async {
        let session = PracticeSession()
        let task = session.hotkeyFired(engine: CountingEngine())
        #expect(session.stage == .proofreading)
        await task?.value
        #expect(session.stage == .success)
    }

    @Test func pressDuringProofreadingIsInert() {
        let session = PracticeSession()
        let engine = CountingEngine()
        session.handle(.sawChord)
        #expect(session.stage == .proofreading)
        let task = session.hotkeyFired(engine: engine)
        #expect(task == nil)
        #expect(session.stage == .proofreading)
        #expect(engine.calls == 0)
    }

    @Test func pressAfterSuccessIsInert() async {
        let session = PracticeSession()
        session.handle(.sawChord)
        session.handle(.proofreadSucceeded)
        let engine = CountingEngine()
        #expect(session.hotkeyFired(engine: engine) == nil)
        #expect(session.stage == .success)
        #expect(engine.calls == 0)
    }

    @Test func pressDuringFailedStateIsInert() {
        let session = PracticeSession()
        session.handle(.sawChord)
        session.handle(.proofreadFailed("boom"))
        let engine = CountingEngine()
        #expect(session.hotkeyFired(engine: engine) == nil)
        #expect(session.stage == .failed("boom"))
        #expect(engine.calls == 0)
    }
}
