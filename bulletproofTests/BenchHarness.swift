import Foundation
@testable import bulletproof

/// Benchmark harness: JSONL cases through a real engine + gate chain, scored
/// on visible behavior with a deliberate asymmetry - staying silent on a
/// fixable typo costs 0.7, pasting something wrong costs everything.

nonisolated struct BenchCase: Equatable, Identifiable, Sendable {
    enum Expected: Equatable, Sendable {
        case fix(acceptable: [String])
        case unchanged
        case reject(allowedReasons: [String])
    }

    let id: String
    let input: String
    let expected: Expected
    let tags: [String]
}

nonisolated enum BenchOutcome: Equatable, Sendable {
    case output(String)
    case rejected(String)
    case error(String)
}

nonisolated enum BenchCorpusError: Error, CustomStringConvertible {
    case duplicateID(String)
    case invalidCase(id: String, reason: String)

    var description: String {
        switch self {
        case .duplicateID(let id): "duplicate case id: \(id)"
        case .invalidCase(let id, let reason): "invalid case \(id): \(reason)"
        }
    }
}

nonisolated enum BenchCorpus {
    private struct RawCase: Decodable {
        struct RawExpected: Decodable {
            let kind: String
            let acceptableOutputs: [String]?
            let allowedReasons: [String]?
        }

        let id: String
        let input: String
        let expected: RawExpected
        let tags: [String]
    }

    /// Fails loudly on malformed cases - a bad row must never silently
    /// vanish from a twenty-minute run.
    static func parse(_ jsonl: String) throws -> [BenchCase] {
        var cases: [BenchCase] = []
        var seen = Set<String>()
        for line in jsonl.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let raw = try JSONDecoder().decode(RawCase.self, from: Data(trimmed.utf8))
            guard seen.insert(raw.id).inserted else {
                throw BenchCorpusError.duplicateID(raw.id)
            }
            let expected: BenchCase.Expected
            switch raw.expected.kind {
            case "fix":
                let acceptable = raw.expected.acceptableOutputs ?? []
                guard !acceptable.isEmpty else {
                    throw BenchCorpusError.invalidCase(id: raw.id, reason: "fix needs acceptableOutputs")
                }
                expected = .fix(acceptable: acceptable)
            case "unchanged":
                expected = .unchanged
            case "reject":
                let reasons = raw.expected.allowedReasons ?? []
                guard !reasons.isEmpty else {
                    throw BenchCorpusError.invalidCase(id: raw.id, reason: "reject needs allowedReasons")
                }
                expected = .reject(allowedReasons: reasons)
            default:
                throw BenchCorpusError.invalidCase(id: raw.id, reason: "unknown kind \(raw.expected.kind)")
            }
            cases.append(BenchCase(id: raw.id, input: raw.input, expected: expected, tags: raw.tags))
        }
        return cases
    }

    static func load(from url: URL) throws -> [BenchCase] {
        try parse(String(contentsOf: url, encoding: .utf8))
    }
}

nonisolated enum BenchScoring {
    struct Scored: Equatable, Sendable {
        let value: Double
        let category: String
    }

    /// Whitespace-insensitive, everything-else-sensitive: capitalization and
    /// punctuation are proofreading quality, not noise.
    static func canonical(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func score(_ benchCase: BenchCase, _ outcome: BenchOutcome) -> Scored {
        switch (benchCase.expected, outcome) {
        case (_, .error):
            return Scored(value: 0.0, category: "engineError")

        case (.fix(let acceptable), .output(let output)):
            if acceptable.map(canonical).contains(canonical(output)) {
                return Scored(value: 1.0, category: "correctFix")
            }
            if canonical(output) == canonical(benchCase.input) {
                return Scored(value: 0.3, category: "missedFix")
            }
            return Scored(value: 0.0, category: "wrongFix")
        case (.fix, .rejected):
            return Scored(value: 0.3, category: "gateBlockedFix")

        case (.unchanged, .output(let output)):
            return canonical(output) == canonical(benchCase.input)
                ? Scored(value: 1.0, category: "preserved")
                : Scored(value: 0.0, category: "corruptedCleanText")
        case (.unchanged, .rejected):
            return Scored(value: 0.3, category: "gateBlockedCleanText")

        case (.reject(let allowed), .rejected(let reason)):
            return allowed.contains(reason)
                ? Scored(value: 1.0, category: "correctReject")
                : Scored(value: 0.0, category: "wrongReasonReject")
        case (.reject, .output(let output)):
            // The threat model is a *changed* paste; a verbatim echo is safe.
            return canonical(output) == canonical(benchCase.input)
                ? Scored(value: 1.0, category: "safeEcho")
                : Scored(value: 0.0, category: "unsafeOutput")
        }
    }
}

nonisolated struct BenchResult: Sendable {
    let benchCase: BenchCase
    let outcome: BenchOutcome
    let ms: Double

    init(case benchCase: BenchCase, outcome: BenchOutcome, ms: Double) {
        self.benchCase = benchCase
        self.outcome = outcome
        self.ms = ms
    }
}

nonisolated struct BenchReport: Codable, Equatable, Sendable {
    struct Failure: Codable, Equatable, Sendable {
        let id: String
        let category: String
        let output: String?
    }

    let engine: String
    let totalCases: Int
    let qualityScore: Double
    let fixRate: Double
    let unchangedPreservation: Double
    let precisionWhenChanged: Double
    let categoryCounts: [String: Int]
    let gateRejections: [String: Int]
    let failures: [Failure]
    let p50Ms: Double
    let p95Ms: Double

    static func aggregate(engine: String, results: [BenchResult]) -> BenchReport {
        var categoryCounts: [String: Int] = [:]
        var gateRejections: [String: Int] = [:]
        var failures: [Failure] = []
        var totalScore = 0.0
        var fixTotal = 0, fixCorrect = 0
        var cleanTotal = 0, cleanPreserved = 0
        var changed = 0, changedAcceptable = 0

        for result in results {
            let scored = BenchScoring.score(result.benchCase, result.outcome)
            totalScore += scored.value
            categoryCounts[scored.category, default: 0] += 1
            if scored.value < 1.0 {
                // Corpus text is hand-authored, so echoing outputs is safe.
                let output: String? = if case .output(let text) = result.outcome { text } else { nil }
                failures.append(Failure(id: result.benchCase.id, category: scored.category, output: output))
            }
            if case .rejected(let reason) = result.outcome {
                gateRejections[reason, default: 0] += 1
            }
            switch result.benchCase.expected {
            case .fix:
                fixTotal += 1
                if scored.category == "correctFix" { fixCorrect += 1 }
            case .unchanged:
                cleanTotal += 1
                if scored.category == "preserved" { cleanPreserved += 1 }
            case .reject:
                break
            }
            if case .output(let output) = result.outcome,
               BenchScoring.canonical(output) != BenchScoring.canonical(result.benchCase.input) {
                changed += 1
                if scored.value == 1.0 { changedAcceptable += 1 }
            }
        }

        let latencies = results.map(\.ms)
        return BenchReport(
            engine: engine,
            totalCases: results.count,
            qualityScore: results.isEmpty ? 0 : totalScore / Double(results.count),
            fixRate: fixTotal == 0 ? 0 : Double(fixCorrect) / Double(fixTotal),
            unchangedPreservation: cleanTotal == 0 ? 0 : Double(cleanPreserved) / Double(cleanTotal),
            precisionWhenChanged: changed == 0 ? 0 : Double(changedAcceptable) / Double(changed),
            categoryCounts: categoryCounts,
            gateRejections: gateRejections,
            failures: failures,
            p50Ms: LatencyStats.percentile(50, of: latencies) ?? 0,
            p95Ms: LatencyStats.percentile(95, of: latencies) ?? 0)
    }
}
