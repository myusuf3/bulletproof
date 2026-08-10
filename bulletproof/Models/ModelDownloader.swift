import Foundation
import Synchronization

/// Downloads one file to a destination with byte-level progress, bridging
/// URLSession's delegate callbacks to async/await and Task cancellation.
nonisolated final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onBytesWritten: @Sendable (Int64) -> Void
    private let state = Mutex<State>(State())

    private struct State {
        var task: URLSessionDownloadTask?
        var continuation: CheckedContinuation<Void, Error>?
        var moveError: Error?
    }

    init(destination: URL, onBytesWritten: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.onBytesWritten = onBytesWritten
    }

    func run(from url: URL) async throws {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = session.downloadTask(with: url)
                state.withLock {
                    $0.task = task
                    $0.continuation = continuation
                }
                // A cancel that raced in before the task existed found nil in
                // onCancel and did nothing - honor it now.
                if Task.isCancelled {
                    task.cancel()
                }
                task.resume()
            }
        } onCancel: {
            state.withLock { $0.task }?.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onBytesWritten(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file is deleted when this callback returns, so move it here.
        do {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse, userInfo: [
                    NSLocalizedDescriptionKey: "HTTP \(http.statusCode) downloading \(downloadTask.originalRequest?.url?.lastPathComponent ?? "file")."
                ])
            }
            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: location, to: destination)
        } catch {
            state.withLock { $0.moveError = error }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, moveError) = state.withLock { state in
            defer { state.continuation = nil }
            return (state.continuation, state.moveError)
        }
        if let error {
            continuation?.resume(throwing: error)
        } else if let moveError {
            continuation?.resume(throwing: moveError)
        } else {
            continuation?.resume()
        }
    }
}

/// Rate-limits delegate-thread progress callbacks before they hop to the main
/// actor for UI updates.
nonisolated final class ByteProgressThrottle: Sendable {
    private let lastReported = Mutex<Int64>(0)
    private let step: Int64
    private let report: @Sendable (Int64) -> Void

    init(step: Int64 = 2_000_000, report: @escaping @Sendable (Int64) -> Void) {
        self.step = step
        self.report = report
    }

    func update(_ bytes: Int64) {
        let shouldReport = lastReported.withLock { last in
            guard bytes - last >= step else { return false }
            last = bytes
            return true
        }
        if shouldReport { report(bytes) }
    }
}
