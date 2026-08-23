import Foundation
import Observation

nonisolated struct DrillWord: Equatable, Sendable {
    let typo: String
    let fix: String
}

/// The practice drill's state machine: a stream of the user's own typos,
/// each answered by typing the fix. Deliberately forgiving on case and
/// whitespace - the drill trains spelling, not shift-key discipline.
@MainActor @Observable
final class DrillSession {
    enum WordState: Equatable {
        case pending, current, correct, missed
    }

    let words: [DrillWord]
    var typed = ""
    private(set) var results: [Bool] = []

    init(words: [DrillWord]) {
        self.words = words
    }

    var index: Int { results.count }
    var isFinished: Bool { index >= words.count }
    var correctCount: Int { results.filter { $0 }.count }
    var missedWords: [DrillWord] { zip(words, results).filter { !$0.1 }.map(\.0) }

    func state(at position: Int) -> WordState {
        if position < results.count {
            return results[position] ? .correct : .missed
        }
        return position == index && !isFinished ? .current : .pending
    }

    func submitCurrent() {
        let answer = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isFinished, !answer.isEmpty else { return }
        let hit = answer.lowercased() == words[index].fix.lowercased()
        results.append(hit)
        typed = ""
    }
}

/// Once-a-day gate with a streak: consecutive days grow it, a skipped day
/// resets it.
@MainActor final class PracticeSchedule {
    static let shared = PracticeSchedule()

    private static let dayKey = "practiceLastDay"
    private static let streakKey = "practiceStreak"

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    var streak: Int { defaults.integer(forKey: Self.streakKey) }

    var completedToday: Bool {
        defaults.string(forKey: Self.dayKey) == Self.dayString(now())
    }

    func completeToday() {
        guard !completedToday else { return }
        let yesterday = Self.dayString(now().addingTimeInterval(-86_400))
        let continued = defaults.string(forKey: Self.dayKey) == yesterday
        defaults.set(continued ? streak + 1 : 1, forKey: Self.streakKey)
        defaults.set(Self.dayString(now()), forKey: Self.dayKey)
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
