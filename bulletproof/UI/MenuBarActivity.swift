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
    /// Toggles while working. MenuBarExtra labels rasterize to a static image
    /// per render, so the "pulse" must be driven by state changes - SwiftUI
    /// animations never tick in the status bar.
    private(set) var pulseTick = false

    let showDelay: Duration
    let minimumShow: Duration
    let failureShow: Duration
    let pulseInterval: Duration

    private var running = false
    private var shownAt: ContinuousClock.Instant?
    // Invalidates in-flight timing tasks when a newer transition supersedes them.
    private var generation = 0

    init(showDelay: Duration = .milliseconds(400),
         minimumShow: Duration = .milliseconds(600),
         failureShow: Duration = .seconds(2),
         pulseInterval: Duration = .milliseconds(500)) {
        self.showDelay = showDelay
        self.minimumShow = minimumShow
        self.failureShow = failureShow
        self.pulseInterval = pulseInterval
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
            pulseTick = true
            while generation == expected {
                try? await Task.sleep(for: pulseInterval)
                guard generation == expected else { break }
                pulseTick.toggle()
            }
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
