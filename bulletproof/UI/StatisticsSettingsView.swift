import AppKit
import SwiftUI

/// Device-local numbers only: what each engine did, why the gate refused,
/// and where the time goes. The answer to "it did nothing" without attaching
/// a debugger.
struct StatisticsSettingsView: View {
    @State private var snapshot = ProofreadStats.Snapshot()

    private static let phases = ["read", "engine", "paste"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let summaries = EngineOutcomeSummary.summaries(from: snapshot)
            if summaries.isEmpty {
                SettingsCard {
                    SettingRow(title: "No proofreads recorded yet",
                               description: "Counts and timings appear after the first proofread. Everything stays on this Mac.") {
                        EmptyView()
                    }
                }
            } else {
                SettingsCard(header: "Outcomes") {
                    ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                        if index > 0 {
                            SettingDivider()
                        }
                        SettingRow(title: summary.engine, description: describe(summary)) {
                            Text("\(summary.total)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                gateRejectionsCard
                latencyCard
            }
            SettingsCard(header: "Log") {
                SettingRow(title: "Proofread log",
                           description: "One line per proofread - outcomes and character counts only, never your text. Cleared at each launch.") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([ProofreadTelemetry.logFileURL])
                    }
                }
            }
        }
        .onAppear { snapshot = ProofreadTelemetry.shared.stats.snapshot() }
    }

    @ViewBuilder
    private var gateRejectionsCard: some View {
        let rejections = snapshot.gateRejections.sorted { $0.value > $1.value }
        if !rejections.isEmpty {
            SettingsCard(header: "Gate rejections") {
                ForEach(Array(rejections.enumerated()), id: \.element.key) { index, entry in
                    if index > 0 {
                        SettingDivider()
                    }
                    SettingRow(title: entry.key) {
                        Text("\(entry.value)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var latencyCard: some View {
        let rows: [(String, Double, Double)] = Self.phases.compactMap { phase in
            guard let p50 = ProofreadTelemetry.shared.stats.phasePercentile(50, of: phase),
                  let p95 = ProofreadTelemetry.shared.stats.phasePercentile(95, of: phase) else {
                return nil
            }
            return (phase, p50, p95)
        }
        if !rows.isEmpty {
            SettingsCard(header: "Latency (this launch)") {
                ForEach(Array(rows.enumerated()), id: \.element.0) { index, row in
                    if index > 0 {
                        SettingDivider()
                    }
                    SettingRow(title: row.0) {
                        Text("p50 \(LatencyStats.display(row.1))   p95 \(LatencyStats.display(row.2))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func describe(_ summary: EngineOutcomeSummary) -> String {
        var parts: [String] = []
        if summary.applied > 0 { parts.append("\(summary.applied) applied") }
        if summary.unchanged > 0 { parts.append("\(summary.unchanged) unchanged") }
        if summary.gateRejected > 0 { parts.append("\(summary.gateRejected) gate-rejected") }
        if summary.errors > 0 { parts.append("\(summary.errors) errors") }
        if summary.aborted > 0 { parts.append("\(summary.aborted) aborted") }
        return parts.joined(separator: " · ")
    }
}
