import Foundation
import Synchronization

nonisolated enum SyncBridge {
    /// Blocks the calling (main) thread by pumping the run loop until the async
    /// operation finishes or the deadline passes. Services callbacks are
    /// synchronous, and a semaphore here would deadlock anything that hops to
    /// the main actor. The deadline stays under the service's NSTimeout so
    /// failures surface as our notification, not the system's silent timeout.
    static func run<T: Sendable>(
        timeout: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) -> Result<T, Error> {
        let box = Mutex<Result<T, Error>?>(nil)
        let task = Task.detached(priority: .userInitiated) {
            let result: Result<T, Error>
            do { result = .success(try await operation()) }
            catch { result = .failure(error) }
            box.withLock { $0 = result }
        }
        let deadline = Date(timeIntervalSinceNow: timeout)
        while box.withLock({ $0 == nil }) && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        guard let result = box.withLock({ $0 }) else {
            task.cancel()
            return .failure(ProofreadingError.timedOut)
        }
        return result
    }
}
