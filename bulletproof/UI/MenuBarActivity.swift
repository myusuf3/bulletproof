import Foundation
import Observation

/// Drives the menu bar icon's busy/failure states. Fast operations never
/// flash the icon (working appears only after showDelay and holds for
/// minimumShow); failures blip regardless so the user has a visible cue
/// beyond the notification.
@MainActor @Observable
final class MenuBarActivity {
    enum Phase: Equatable {
        case idle, working, failed
    }

    private(set) var phase: Phase = .idle

    let showDelay: Duration
    let minimumShow: Duration
    let failureShow: Duration

    private var running = false
    private var shownAt: ContinuousClock.Instant?
    // Invalidates in-flight timing tasks when a newer transition supersedes them.
    private var generation = 0

    init(showDelay: Duration = .milliseconds(400),
         minimumShow: Duration = .milliseconds(600),
         failureShow: Duration = .seconds(2)) {
        self.showDelay = showDelay
        self.minimumShow = minimumShow
        self.failureShow = failureShow
    }

    func begin() {
        running = true
        shownAt = nil
        phase = .idle
        generation += 1
        let expected = generation
        Task {
            try? await Task.sleep(for: showDelay)
            guard generation == expected, running else { return }
            phase = .working
            shownAt = ContinuousClock.now
        }
    }

    func end(success: Bool) {
        running = false
        generation += 1
        let expected = generation

        guard success else {
            phase = .failed
            Task {
                try? await Task.sleep(for: failureShow)
                guard generation == expected else { return }
                phase = .idle
            }
            return
        }

        guard phase == .working else {
            phase = .idle
            return
        }
        let elapsed = shownAt.map { ContinuousClock.now - $0 } ?? minimumShow
        let remaining = minimumShow - elapsed
        guard remaining > .zero else {
            phase = .idle
            return
        }
        Task {
            try? await Task.sleep(for: remaining)
            guard generation == expected else { return }
            phase = .idle
        }
    }
}
