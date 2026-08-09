import Foundation
import Testing
@testable import bulletproof

private struct FakeEngine: ProofreadingEngine {
    var result: Result<String, ProofreadingError>
    var delay: Duration = .zero

    func proofread(_ text: String) async throws -> String {
        try await Task.sleep(for: delay)
        return try result.get()
    }
}

struct SyncBridgeTests {
    @Test func returnsEngineResult() {
        let engine = FakeEngine(result: .success("the cat"))
        let outcome = SyncBridge.run(timeout: 5) { try await engine.proofread("teh cat") }
        #expect(try! outcome.get() == "the cat")
    }

    @Test func propagatesEngineError() {
        let engine = FakeEngine(result: .failure(.notImplemented("stub")))
        let outcome = SyncBridge.run(timeout: 5) { try await engine.proofread("x") }
        guard case .failure(let error as ProofreadingError) = outcome,
              case .notImplemented = error else {
            Issue.record("Expected notImplemented, got \(outcome)")
            return
        }
    }

    @Test func timesOutSlowEngines() {
        let engine = FakeEngine(result: .success("late"), delay: .seconds(10))
        let outcome = SyncBridge.run(timeout: 0.3) { try await engine.proofread("x") }
        guard case .failure(let error as ProofreadingError) = outcome,
              case .timedOut = error else {
            Issue.record("Expected timedOut, got \(outcome)")
            return
        }
    }
}
