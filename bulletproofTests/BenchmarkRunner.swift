import Foundation
import FoundationModels
import Testing
@testable import bulletproof

/// Anchor for locating bundled corpus resources from Swift Testing suites.
final class BenchBundleAnchor {}

nonisolated func benchCorpusURL() throws -> URL {
    try #require(Bundle(for: BenchBundleAnchor.self)
        .url(forResource: "bench-corpus", withExtension: "jsonl"))
}

/// Runs in the normal suite: a malformed corpus fails CI immediately, not
/// twenty minutes into an opt-in benchmark run.
struct BenchCorpusFileTests {
    @Test func bundledCorpusParsesAndValidates() throws {
        let cases = try BenchCorpus.load(from: benchCorpusURL())
        #expect(cases.count >= 40)
        let fixes = cases.filter { if case .fix = $0.expected { true } else { false } }
        let unchanged = cases.filter { $0.expected == .unchanged }
        #expect(fixes.count >= 15)
        #expect(unchanged.count >= 15)
    }
}

/// The full benchmark: every case through the real gate chain against every
/// available engine. Opt-in and slow - minutes per engine. Run with:
///
///   xcodebuild test ... -only-testing:bulletproofTests/BenchmarkRunner \
///       TEST_RUNNER_BULLETPROOF_BENCH=1
///
/// Reports land in /tmp/bulletproof-bench/<engine>.json; copy into the repo
/// next to prior runs to make quality diffs reviewable.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BULLETPROOF_BENCH"] == "1"),
       .serialized)
struct BenchmarkRunner {
    private static let outputDir = URL(fileURLWithPath: "/tmp/bulletproof-bench")

    @Test func runCorpusThroughAvailableEngines() async throws {
        let cases = try BenchCorpus.load(from: benchCorpusURL())
        var engines: [(String, any ProofreadingEngine)] = []
        if case .available = AppleIntelligenceEngine.model.availability {
            engines.append(("appleIntelligence", AppleIntelligenceEngine()))
        }
        let store = ModelStore()
        for id in store.installedModelIDs() {
            engines.append(("local(\(id))", LocalModelEngine(modelDirectory: store.directory(for: id))))
        }
        try #require(!engines.isEmpty, "no engines available to benchmark")

        try FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)
        for (name, engine) in engines {
            let gated = OutputGatedEngine(wrapped: engine)
            await gated.prewarm()
            var results: [BenchResult] = []
            for benchCase in cases {
                let start = ContinuousClock.now
                let outcome: BenchOutcome
                do {
                    let output = try await withTimeout(seconds: 55) {
                        try await gated.proofread(benchCase.input)
                    }
                    outcome = .output(output)
                } catch {
                    outcome = switch ProofreadOutcome.from(error) {
                    case .gateRejected(let reason): .rejected(reason)
                    case .engineError(let kind): .error(kind)
                    default: .error("unknown")
                    }
                }
                results.append(BenchResult(
                    case: benchCase, outcome: outcome,
                    ms: (ContinuousClock.now - start) / .milliseconds(1)))
            }

            let report = BenchReport.aggregate(engine: name, results: results)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let file = Self.outputDir.appendingPathComponent(
                "\(name.replacingOccurrences(of: "/", with: "_")).json")
            try encoder.encode(report).write(to: file)
            print("BENCH \(name): quality \(report.qualityScore) fixRate \(report.fixRate) preservation \(report.unchangedPreservation) p50 \(report.p50Ms)ms -> \(file.path)")

            // Floors, not targets: fail loudly if an engine is grossly broken.
            #expect(report.qualityScore > 0.5, "quality collapsed for \(name)")
        }
    }
}
