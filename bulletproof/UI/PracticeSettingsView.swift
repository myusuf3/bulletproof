import SwiftUI

/// Daily drill home: your most-corrected words and the once-a-day practice
/// run over them.
struct PracticeSettingsView: View {
    @State private var top: [(typo: String, fix: String, count: Int)] = []
    @State private var completedToday = false
    @State private var streak = 0

    private static let minimumWords = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard {
                SettingRow(title: completedToday ? "Done for today ✓" : "Daily drill",
                           description: drillDescription) {
                    Button("Start Today's Drill") { startDrill() }
                        .disabled(completedToday || top.count < Self.minimumWords)
                }
                if streak > 0 {
                    SettingDivider()
                    SettingRow(title: "Streak",
                               description: "Consecutive days practiced. Miss a day and it resets.") {
                        Text("\(streak) day\(streak == 1 ? "" : "s") 🔥")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            SettingsCard(header: "Your most-corrected words") {
                if top.isEmpty {
                    SettingRow(title: "Nothing tracked yet",
                               description: "As bulletproof fixes your typos, the recurring ones show up here - single words only, stored on this Mac, never sent anywhere.") {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(top.enumerated()), id: \.element.typo) { index, entry in
                        if index > 0 {
                            SettingDivider()
                        }
                        SettingRow(title: "\(entry.typo) → \(entry.fix)") {
                            Text("\(entry.count)×")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .onAppear(perform: refresh)
    }

    private var drillDescription: String {
        if completedToday {
            return "Come back tomorrow to keep the streak going."
        }
        if top.count < Self.minimumWords {
            return "Practice unlocks once bulletproof has seen \(Self.minimumWords) recurring typos (\(top.count) so far). Keep writing."
        }
        return "A Monkeytype-style run over the words you mistype most - once a day."
    }

    private func startDrill() {
        // The pane sits open behind the drill window with onAppear-stale
        // state, so the once-a-day gate must be re-checked at click time.
        guard !PracticeSchedule.shared.completedToday else {
            refresh()
            return
        }
        // Two shuffled passes over the top typos, capped - enough reps to
        // stick without dragging.
        let pool = CorrectionStats.shared.topFixes(limit: 10)
            .map { DrillWord(typo: $0.typo, fix: $0.fix) }
        let sequence = Array((pool.shuffled() + pool.shuffled()).prefix(15))
        PracticeDrillWindowController.shared.show(words: sequence, onClose: refresh)
    }

    private func refresh() {
        top = CorrectionStats.shared.topFixes(limit: 10)
        completedToday = PracticeSchedule.shared.completedToday
        streak = PracticeSchedule.shared.streak
    }
}
