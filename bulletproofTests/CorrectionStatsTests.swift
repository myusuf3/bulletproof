import Foundation
import Testing
@testable import bulletproof

@MainActor
struct CorrectionStatsTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "stats-test-\(UUID().uuidString)")!
    }

    @Test func singleWordFixesAreCounted() {
        let stats = CorrectionStats(defaults: freshDefaults())
        stats.record(original: "did you recieve my email", corrected: "did you receive my email")
        stats.record(original: "we recieve mail daily", corrected: "we receive mail daily")
        let top = stats.topFixes(limit: 5)
        #expect(top.first?.typo == "recieve")
        #expect(top.first?.fix == "receive")
        #expect(top.first?.count == 2)
    }

    @Test func multiWordRewritesAreNotTracked() {
        // Only clean one-word substitutions are drillable typos.
        let stats = CorrectionStats(defaults: freshDefaults())
        stats.record(original: "their welcom here", corrected: "they're welcome here")
        #expect(stats.trackedCount == 0)
    }

    @Test func punctuationOnlyAndCaseOnlyChangesAreSkipped() {
        let stats = CorrectionStats(defaults: freshDefaults())
        stats.record(original: "whats the plan", corrected: "whats the plan?")
        stats.record(original: "i think so", corrected: "I think so")
        #expect(stats.trackedCount == 0)
    }

    @Test func oneOffTyposAreNotDrillMaterial() {
        let stats = CorrectionStats(defaults: freshDefaults())
        stats.record(original: "a wierd day", corrected: "a weird day")
        #expect(stats.trackedCount == 1)
        #expect(stats.topFixes(limit: 5).isEmpty)
    }

    @Test func topFixesSortByCountDescending() {
        let stats = CorrectionStats(defaults: freshDefaults())
        for _ in 0..<3 {
            stats.record(original: "teh cat", corrected: "the cat")
        }
        for _ in 0..<2 {
            stats.record(original: "a wierd day", corrected: "a weird day")
        }
        let top = stats.topFixes(limit: 5)
        #expect(top.map(\.typo) == ["teh", "wierd"])
    }

    @Test func countsSurviveRelaunch() {
        let defaults = freshDefaults()
        for _ in 0..<2 {
            CorrectionStats(defaults: defaults).record(original: "teh cat", corrected: "the cat")
        }
        #expect(CorrectionStats(defaults: defaults).topFixes(limit: 1).first?.typo == "teh")
    }

    @Test func trackedEntriesAreCapped() {
        let stats = CorrectionStats(defaults: freshDefaults())
        for i in 0..<400 {
            stats.record(original: "\(Self.nonsenseWord(i)) here", corrected: "word here")
        }
        #expect(stats.trackedCount <= 300)
    }

    @Test func evictionKeepsRecurringWordsOverOneOffs() {
        let stats = CorrectionStats(defaults: freshDefaults())
        for _ in 0..<5 {
            stats.record(original: "did you recieve it", corrected: "did you receive it")
        }
        for i in 0..<350 {
            stats.record(original: "\(Self.nonsenseWord(i)) here", corrected: "word here")
        }
        #expect(stats.trackedCount <= 300)
        #expect(stats.topFixes(limit: 1).first?.typo == "recieve")
    }

    @Test func newTyposStillAccumulateWhenTheTableIsFull() {
        // A full table of recurring entries must not evict every newcomer at
        // count 1 in the same call it arrived - that freezes the tracked set.
        let stats = CorrectionStats(defaults: freshDefaults())
        for i in 0..<300 {
            for _ in 0..<2 {
                stats.record(original: "\(Self.nonsenseWord(i)) here", corrected: "word here")
            }
        }
        for _ in 0..<2 {
            stats.record(original: "freshtypo here", corrected: "fresh here")
        }
        #expect(stats.trackedCount <= 300)
        #expect(stats.topFixes(limit: 300).contains { $0.typo == "freshtypo" && $0.count == 2 })
    }

    private static func nonsenseWord(_ i: Int) -> String {
        let a = Character(UnicodeScalar(97 + UInt8(i % 26)))
        let b = Character(UnicodeScalar(97 + UInt8((i / 26) % 26)))
        return "zz\(a)\(b)blorp"
    }
}

@MainActor
struct DrillSessionTests {
    private let words = [
        DrillWord(typo: "teh", fix: "the"),
        DrillWord(typo: "recieve", fix: "receive"),
        DrillWord(typo: "wierd", fix: "weird"),
    ]

    @Test func correctSubmissionsAdvanceAndScore() {
        let session = DrillSession(words: words)
        #expect(session.state(at: 0) == .current)
        #expect(session.state(at: 1) == .pending)
        session.typed = "the"
        session.submitCurrent()
        #expect(session.state(at: 0) == .correct)
        #expect(session.state(at: 1) == .current)
        #expect(!session.isFinished)
    }

    @Test func wrongSubmissionIsMissedButAdvances() {
        let session = DrillSession(words: words)
        session.typed = "thier"
        session.submitCurrent()
        #expect(session.state(at: 0) == .missed)
    }

    @Test func matchingIsCaseAndWhitespaceForgiving() {
        let session = DrillSession(words: words)
        session.typed = "  The "
        session.submitCurrent()
        #expect(session.state(at: 0) == .correct)
    }

    @Test func finishingReportsScore() {
        let session = DrillSession(words: words)
        for answer in ["the", "nope", "weird"] {
            session.typed = answer
            session.submitCurrent()
        }
        #expect(session.isFinished)
        #expect(session.correctCount == 2)
        #expect(session.missedWords.map(\.typo) == ["recieve"])
    }

    @Test func emptySubmissionIsIgnored() {
        let session = DrillSession(words: words)
        session.typed = "   "
        session.submitCurrent()
        #expect(session.state(at: 0) == .current)
    }
}

@MainActor
struct PracticeScheduleTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "sched-test-\(UUID().uuidString)")!
    }

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        return formatter.date(from: string)!
    }

    @Test func freshScheduleAllowsPracticeAndHasNoStreak() {
        let schedule = PracticeSchedule(defaults: freshDefaults(), now: { self.date("2026-08-20 10:00") })
        #expect(!schedule.completedToday)
        #expect(schedule.streak == 0)
    }

    @Test func completingTodayBlocksASecondRunAndStartsStreak() {
        let schedule = PracticeSchedule(defaults: freshDefaults(), now: { self.date("2026-08-20 10:00") })
        schedule.completeToday()
        #expect(schedule.completedToday)
        #expect(schedule.streak == 1)
    }

    @Test func consecutiveDaysGrowTheStreak() {
        let defaults = freshDefaults()
        PracticeSchedule(defaults: defaults, now: { self.date("2026-08-20 10:00") }).completeToday()
        let nextDay = PracticeSchedule(defaults: defaults, now: { self.date("2026-08-21 09:00") })
        #expect(!nextDay.completedToday)
        nextDay.completeToday()
        #expect(nextDay.streak == 2)
    }

    @Test func skippingADayResetsTheStreak() {
        let defaults = freshDefaults()
        PracticeSchedule(defaults: defaults, now: { self.date("2026-08-20 10:00") }).completeToday()
        let later = PracticeSchedule(defaults: defaults, now: { self.date("2026-08-23 10:00") })
        later.completeToday()
        #expect(later.streak == 1)
    }
}
