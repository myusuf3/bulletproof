import Foundation
import Testing
@testable import bulletproof

struct ProofreadOutcomeTests {
    @Test func labelsAreStableAndCarryReasons() {
        #expect(ProofreadOutcome.applied.label == "APPLIED")
        #expect(ProofreadOutcome.unchanged.label == "UNCHANGED")
        #expect(ProofreadOutcome.gateRejected("lowOverlap").label == "GATE_REJECT(lowOverlap)")
        #expect(ProofreadOutcome.engineError("timeout").label == "ENGINE_ERROR(timeout)")
        #expect(ProofreadOutcome.aborted("app-changed").label == "ABORTED(app-changed)")
    }

    @Test func classifiesEveryProofreadingErrorToAStableKind() {
        #expect(ProofreadOutcome.from(ProofreadingError.unusableOutput(.lowOverlap))
                == .gateRejected("lowOverlap"))
        #expect(ProofreadOutcome.from(ProofreadingError.unusableOutput(.introducedMisspelling))
                == .gateRejected("introducedMisspelling"))
        #expect(ProofreadOutcome.from(ProofreadingError.timedOut) == .engineError("timeout"))
        #expect(ProofreadOutcome.from(ProofreadingError.engineUnavailable(reason: "x"))
                == .engineError("unavailable"))
        #expect(ProofreadOutcome.from(ProofreadingError.inputTooLong) == .engineError("input-too-long"))
        #expect(ProofreadOutcome.from(ProofreadingError.guardrailViolation) == .engineError("guardrail"))
        #expect(ProofreadOutcome.from(ProofreadingError.emptyInput) == .engineError("empty-input"))
        struct Mystery: Error {}
        #expect(ProofreadOutcome.from(Mystery()) == .engineError("unknown"))
    }

    @Test func inferenceFailureKeepsOnlyTheKindNeverTheMessage() {
        // The log must never leak an underlying error message that could
        // quote the user's text.
        let underlying = NSError(domain: "test", code: 1,
                                 userInfo: [NSLocalizedDescriptionKey: "failed on: secret text"])
        let outcome = ProofreadOutcome.from(ProofreadingError.inferenceFailed(underlying: underlying))
        #expect(outcome == .engineError("inference"))
    }
}

struct ProofreadEventTests {
    @Test func logDescriptionCarriesCountsPhasesAndOutcome() {
        let event = ProofreadEvent(entryPoint: .hotkey, engine: "appleIntelligence",
                                   inputChars: 240, outputChars: 238,
                                   outcome: .applied,
                                   phases: [.init(name: "read", ms: 12.4),
                                            .init(name: "engine", ms: 950.2),
                                            .init(name: "paste", ms: 320.0)],
                                   totalMs: 1282.6)
        #expect(event.logDescription ==
                "HOTKEY engine=appleIntelligence in=240 out=238 read=12ms engine=950ms paste=320ms total=1282ms -> APPLIED")
    }

    @Test func logDescriptionOmitsWhatNeverHappened() {
        let event = ProofreadEvent(entryPoint: .service, engine: "local(mlx-community/Qwen3-4B)",
                                   inputChars: 0, outputChars: nil,
                                   outcome: .aborted("secure-field"), phases: [], totalMs: 3.2)
        #expect(event.logDescription ==
                "SERVICE engine=local(mlx-community/Qwen3-4B) in=0 total=3ms -> ABORTED(secure-field)")
    }
}

struct EngineChoiceLabelTests {
    @Test func labelsIdentifyTheEngineWithoutDecoration() {
        #expect(EngineChoice.appleIntelligence.telemetryLabel == "appleIntelligence")
        #expect(EngineChoice.local(modelID: "mlx-community/Qwen3-4B").telemetryLabel
                == "local(mlx-community/Qwen3-4B)")
    }
}

struct LatencyPercentileTests {
    @Test func emptySamplesHaveNoPercentile() {
        #expect(LatencyStats.percentile(50, of: []) == nil)
    }

    @Test func nearestRankPercentiles() {
        let samples: [Double] = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
        #expect(LatencyStats.percentile(50, of: samples) == 50)
        #expect(LatencyStats.percentile(95, of: samples) == 100)
        #expect(LatencyStats.percentile(50, of: [42]) == 42)
    }

    @Test func unsortedInputIsHandled() {
        #expect(LatencyStats.percentile(50, of: [90, 10, 50]) == 50)
    }
}

struct ProofreadStatsTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "telemetry-test-\(UUID().uuidString)")!
    }

    private func event(outcome: ProofreadOutcome,
                       engine: String = "appleIntelligence",
                       phases: [ProofreadEvent.Phase] = []) -> ProofreadEvent {
        ProofreadEvent(entryPoint: .hotkey, engine: engine, inputChars: 10, outputChars: nil,
                       outcome: outcome, phases: phases, totalMs: 100)
    }

    @Test func countsOutcomesPerEngine() {
        let stats = ProofreadStats(defaults: freshDefaults())
        stats.record(event(outcome: .applied))
        stats.record(event(outcome: .applied))
        stats.record(event(outcome: .gateRejected("lowOverlap"), engine: "local(qwen)"))
        let snapshot = stats.snapshot()
        #expect(snapshot.outcomeCounts["appleIntelligence|APPLIED"] == 2)
        #expect(snapshot.outcomeCounts["local(qwen)|GATE_REJECT(lowOverlap)"] == 1)
    }

    @Test func gateRejectionsAccumulateAHistogramByReason() {
        let stats = ProofreadStats(defaults: freshDefaults())
        stats.record(event(outcome: .gateRejected("lowOverlap")))
        stats.record(event(outcome: .gateRejected("lowOverlap")))
        stats.record(event(outcome: .gateRejected("emptyOutput")))
        #expect(stats.snapshot().gateRejections == ["lowOverlap": 2, "emptyOutput": 1])
    }

    @Test func countsSurviveRelaunch() {
        let defaults = freshDefaults()
        ProofreadStats(defaults: defaults).record(event(outcome: .applied))
        // A fresh instance over the same store sees the persisted counts.
        #expect(ProofreadStats(defaults: defaults).snapshot()
            .outcomeCounts["appleIntelligence|APPLIED"] == 1)
    }

    @Test func phasePercentilesComeFromCompletedFlowsOnly() {
        let stats = ProofreadStats(defaults: freshDefaults())
        for ms in [100.0, 200.0, 300.0] {
            stats.record(event(outcome: .applied, phases: [.init(name: "engine", ms: ms)]))
        }
        // Failures must not pollute the visible-latency picture.
        stats.record(event(outcome: .engineError("timeout"),
                           phases: [.init(name: "engine", ms: 55_000)]))
        #expect(stats.phasePercentile(50, of: "engine") == 200)
    }
}

struct EngineOutcomeSummaryTests {
    @Test func groupsOutcomeCountsByEngine() {
        var snapshot = ProofreadStats.Snapshot()
        snapshot.outcomeCounts = [
            "appleIntelligence|APPLIED": 5,
            "appleIntelligence|GATE_REJECT(lowOverlap)": 2,
            "appleIntelligence|GATE_REJECT(emptyOutput)": 1,
            "local(qwen)|UNCHANGED": 3,
            "local(qwen)|ENGINE_ERROR(timeout)": 1,
            "local(qwen)|ABORTED(app-changed)": 4,
        ]
        let summaries = EngineOutcomeSummary.summaries(from: snapshot)
        #expect(summaries.map(\.engine) == ["appleIntelligence", "local(qwen)"])
        #expect(summaries[0].applied == 5)
        #expect(summaries[0].gateRejected == 3)
        #expect(summaries[1].unchanged == 3)
        #expect(summaries[1].errors == 1)
        #expect(summaries[1].aborted == 4)
        #expect(summaries[1].total == 8)
    }

    @Test func emptySnapshotHasNoSummaries() {
        #expect(EngineOutcomeSummary.summaries(from: ProofreadStats.Snapshot()).isEmpty)
    }
}

struct LatencyDisplayTests {
    @Test func millisecondsReadAsMSBelowASecond() {
        #expect(LatencyStats.display(142.6) == "143 ms")
    }

    @Test func aSecondAndUpReadsAsSeconds() {
        #expect(LatencyStats.display(1440) == "1.4 s")
        #expect(LatencyStats.display(12_600) == "12.6 s")
    }
}

struct ProofreadLogTests {
    @Test func writesHeaderAppendsLinesAndTruncatesOnNewLaunch() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prooflog-\(UUID().uuidString)")

        let log = ProofreadLog(directory: dir)
        log.append("HOTKEY engine=x in=1 total=1ms -> APPLIED")
        log.flush()
        var contents = try String(contentsOf: dir.appendingPathComponent("proofreads.log"),
                                  encoding: .utf8)
        #expect(contents.hasPrefix("# bulletproof proofread log"))
        #expect(contents.contains("-> APPLIED"))

        // A new launch starts a fresh file - this log is a flight recorder,
        // not an archive.
        let relaunched = ProofreadLog(directory: dir)
        relaunched.flush()
        contents = try String(contentsOf: dir.appendingPathComponent("proofreads.log"),
                              encoding: .utf8)
        #expect(!contents.contains("-> APPLIED"))
    }

    @Test func appendedLinesAreTimestamped() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prooflog-\(UUID().uuidString)")
        let log = ProofreadLog(directory: dir)
        log.append("SERVICE engine=x in=5 total=2ms -> UNCHANGED")
        log.flush()
        let line = try String(contentsOf: dir.appendingPathComponent("proofreads.log"),
                              encoding: .utf8)
            .split(separator: "\n").last.map(String.init) ?? ""
        // [HH:mm:ss.SSS] prefix.
        #expect(line.range(of: #"^\[\d{2}:\d{2}:\d{2}\.\d{3}\] "#,
                           options: .regularExpression) != nil)
    }
}
