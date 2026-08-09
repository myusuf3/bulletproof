import Testing
@testable import bulletproof

struct PracticeReducerTests {
    @Test func happyPath() {
        var stage = PracticeStage.selectAll
        stage = PracticeReducer.next(stage, .sawSelectAll)
        #expect(stage == .chord)
        stage = PracticeReducer.next(stage, .sawChord)
        #expect(stage == .proofreading)
        stage = PracticeReducer.next(stage, .proofreadSucceeded)
        #expect(stage == .success)
    }

    @Test func chordBeforeSelectAllStillCounts() {
        #expect(PracticeReducer.next(.selectAll, .sawChord) == .proofreading)
    }

    @Test func failureAllowsRetry() {
        var stage = PracticeReducer.next(.proofreading, .proofreadFailed("boom"))
        #expect(stage == .failed("boom"))
        stage = PracticeReducer.next(stage, .retry)
        #expect(stage == .chord)
    }

    @Test func irrelevantEventsAreNoOps() {
        #expect(PracticeReducer.next(.proofreading, .sawSelectAll) == .proofreading)
        #expect(PracticeReducer.next(.success, .sawChord) == .success)
        #expect(PracticeReducer.next(.selectAll, .proofreadSucceeded) == .selectAll)
        #expect(PracticeReducer.next(.chord, .retry) == .chord)
    }
}
