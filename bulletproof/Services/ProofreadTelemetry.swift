import Foundation
import Synchronization

/// Device-local flight recorder. Every proofread - hotkey, Services menu,
/// Shortcuts - leaves one log line and bumps counters, so "it did nothing"
/// has an answer: gate rejection, engine error, or an aborted flow. Records
/// character counts and outcomes only, never the text.
nonisolated enum ProofreadEntryPoint: String, Sendable {
    case hotkey, service, intent
}

nonisolated enum ProofreadOutcome: Equatable, Sendable {
    case applied
    case unchanged
    case gateRejected(String)
    case engineError(String)
    case aborted(String)

    var label: String {
        switch self {
        case .applied: "APPLIED"
        case .unchanged: "UNCHANGED"
        case .gateRejected(let reason): "GATE_REJECT(\(reason))"
        case .engineError(let kind): "ENGINE_ERROR(\(kind))"
        case .aborted(let reason): "ABORTED(\(reason))"
        }
    }

    /// Stable kinds only - never the message, which can quote user text.
    static func from(_ error: Error) -> ProofreadOutcome {
        guard let error = error as? ProofreadingError else { return .engineError("unknown") }
        return switch error {
        case .unusableOutput(let reason): .gateRejected(String(describing: reason))
        case .timedOut: .engineError("timeout")
        case .engineUnavailable: .engineError("unavailable")
        case .inputTooLong: .engineError("input-too-long")
        case .guardrailViolation: .engineError("guardrail")
        case .emptyInput: .engineError("empty-input")
        case .inferenceFailed: .engineError("inference")
        case .notImplemented: .engineError("not-implemented")
        }
    }
}

nonisolated struct ProofreadEvent: Sendable {
    struct Phase: Equatable, Sendable {
        let name: String
        let ms: Double
    }

    let entryPoint: ProofreadEntryPoint
    let engine: String
    let inputChars: Int
    let outputChars: Int?
    let outcome: ProofreadOutcome
    let phases: [Phase]
    let totalMs: Double

    var logDescription: String {
        var parts = [entryPoint.rawValue.uppercased(), "engine=\(engine)", "in=\(inputChars)"]
        if let outputChars {
            parts.append("out=\(outputChars)")
        }
        parts += phases.map { "\($0.name)=\(Int($0.ms))ms" }
        parts.append("total=\(Int(totalMs))ms")
        parts.append("-> \(outcome.label)")
        return parts.joined(separator: " ")
    }
}

extension EngineChoice {
    var telemetryLabel: String {
        switch self {
        case .appleIntelligence: "appleIntelligence"
        case .local(let modelID): "local(\(modelID))"
        }
    }
}

nonisolated enum LatencyStats {
    /// Nearest-rank percentile.
    static func percentile(_ p: Double, of samples: [Double]) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[max(0, min(sorted.count - 1, rank - 1))]
    }

    static func display(_ ms: Double) -> String {
        ms < 1000 ? "\(Int(ms.rounded())) ms" : String(format: "%.1f s", ms / 1000)
    }
}

/// The per-engine view of the outcome counters, for the Statistics pane.
nonisolated struct EngineOutcomeSummary: Equatable, Sendable, Identifiable {
    let engine: String
    var applied = 0
    var unchanged = 0
    var gateRejected = 0
    var errors = 0
    var aborted = 0

    var id: String { engine }
    var total: Int { applied + unchanged + gateRejected + errors + aborted }

    static func summaries(from snapshot: ProofreadStats.Snapshot) -> [EngineOutcomeSummary] {
        var byEngine: [String: EngineOutcomeSummary] = [:]
        for (key, count) in snapshot.outcomeCounts {
            guard let separator = key.firstIndex(of: "|") else { continue }
            let engine = String(key[..<separator])
            let label = String(key[key.index(after: separator)...])
            var summary = byEngine[engine] ?? EngineOutcomeSummary(engine: engine)
            if label == "APPLIED" {
                summary.applied += count
            } else if label == "UNCHANGED" {
                summary.unchanged += count
            } else if label.hasPrefix("GATE_REJECT") {
                summary.gateRejected += count
            } else if label.hasPrefix("ENGINE_ERROR") {
                summary.errors += count
            } else if label.hasPrefix("ABORTED") {
                summary.aborted += count
            }
            byEngine[engine] = summary
        }
        return byEngine.values.sorted { $0.engine < $1.engine }
    }
}

/// Counters persist across launches; latency samples are per-launch and come
/// from completed flows only, so failures never pollute the visible-latency
/// picture. Per-phase percentiles are computed independently - each answers
/// "how slow is this stage at its tail", not "what was this stage on the
/// worst end-to-end trace".
nonisolated final class ProofreadStats: Sendable {
    struct Snapshot: Codable, Equatable, Sendable {
        var outcomeCounts: [String: Int] = [:]
        var gateRejections: [String: Int] = [:]
    }

    private static let snapshotKey = "proofreadStats"
    private static let reservoirCap = 512

    // UserDefaults is documented thread-safe; it just predates Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let state: Mutex<State>

    private struct State {
        var snapshot: Snapshot
        var phaseSamples: [String: [Double]] = [:]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.snapshotKey)
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
        state = Mutex(State(snapshot: saved))
    }

    func record(_ event: ProofreadEvent) {
        let snapshot = state.withLock { state in
            state.snapshot.outcomeCounts["\(event.engine)|\(event.outcome.label)", default: 0] += 1
            if case .gateRejected(let reason) = event.outcome {
                state.snapshot.gateRejections[reason, default: 0] += 1
            }
            if event.outcome == .applied || event.outcome == .unchanged {
                for phase in event.phases {
                    var samples = state.phaseSamples[phase.name, default: []]
                    if samples.count >= Self.reservoirCap {
                        samples.removeFirst()
                    }
                    samples.append(phase.ms)
                    state.phaseSamples[phase.name] = samples
                }
            }
            return state.snapshot
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.snapshotKey)
        }
    }

    func snapshot() -> Snapshot {
        state.withLock { $0.snapshot }
    }

    func phasePercentile(_ p: Double, of phase: String) -> Double? {
        LatencyStats.percentile(p, of: state.withLock { $0.phaseSamples[phase] ?? [] })
    }
}

/// Human-readable append-only file, truncated with a fresh header on every
/// launch - a flight recorder, not an archive. Writes happen on a utility
/// queue so the proofread path never blocks on disk.
nonisolated final class ProofreadLog: Sendable {
    private let queue = DispatchQueue(label: "com.mahdiyusuf.bulletproof.proofread-log", qos: .utility)
    private let fileURL: URL

    init(directory: URL) {
        let url = directory.appendingPathComponent("proofreads.log")
        fileURL = url
        queue.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let header = "# bulletproof proofread log - truncated each launch; counts and outcomes only, never text\n"
            try? header.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func append(_ line: String) {
        let stamped = "[\(Self.timestamp())] \(line)\n"
        let url = fileURL
        queue.async {
            guard let data = stamped.data(using: .utf8),
                  let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    /// Blocks until queued writes have landed - for tests and bug reports.
    func flush() {
        queue.sync {}
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}

nonisolated final class ProofreadTelemetry: Sendable {
    static let shared = ProofreadTelemetry()

    static let logDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("bulletproof/Logs")
    static var logFileURL: URL { logDirectory.appendingPathComponent("proofreads.log") }

    let stats = ProofreadStats()
    private let log = ProofreadLog(directory: ProofreadTelemetry.logDirectory)

    func record(_ event: ProofreadEvent) {
        log.append(event.logDescription)
        stats.record(event)
    }
}
