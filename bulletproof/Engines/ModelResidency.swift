import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Thrown before MLX is touched when the snapshot is incomplete; the engine
/// maps this to .engineUnavailable with re-download guidance.
nonisolated struct ModelFilesMissingError: Error {
    let directory: URL
}

/// Keeps at most one loaded resource resident, keyed by directory.
/// Single-flight: concurrent callers for the same directory await one load.
/// Evicts after idleTimeout without use, or on explicit request. Generic so
/// the state machine is unit-testable with a fake loader.
actor ResidencyCache<Resource: Sendable> {
    private let loader: @Sendable (URL) async throws -> Resource
    private let idleTimeout: Duration
    private let onEvict: @Sendable () -> Void

    private var resident: (directory: URL, resource: Resource)?
    private var inFlight: (directory: URL, task: Task<Resource, Error>)?
    // Invalidates stale idle timers, same pattern as MenuBarActivity.
    private var idleGeneration = 0

    init(idleTimeout: Duration,
         onEvict: @escaping @Sendable () -> Void = {},
         loader: @escaping @Sendable (URL) async throws -> Resource) {
        self.idleTimeout = idleTimeout
        self.onEvict = onEvict
        self.loader = loader
    }

    func resource(for directory: URL) async throws -> Resource {
        if let resident, resident.directory == directory {
            scheduleEviction()
            return resident.resource
        }
        if let inFlight {
            if inFlight.directory == directory {
                return try await inFlight.task.value
            }
            // Model switched mid-load; the old load's memory frees on completion.
            inFlight.task.cancel()
        }
        evictNow()
        let task = Task { [loader] in try await loader(directory) }
        inFlight = (directory, task)
        defer {
            if inFlight?.directory == directory {
                inFlight = nil
            }
        }
        // A failed load caches nothing - the next request retries.
        let resource = try await task.value
        resident = (directory, resource)
        scheduleEviction()
        return resource
    }

    /// Restarts the idle clock; call after each completed use.
    func touch() {
        guard resident != nil else { return }
        scheduleEviction()
    }

    func evictNow() {
        guard resident != nil else { return }
        resident = nil
        idleGeneration += 1
        onEvict()
    }

    /// Evicts unless the resident directory matches (nil keeps nothing).
    func retainOnly(_ directory: URL?) {
        guard let resident, resident.directory != directory else { return }
        _ = resident
        evictNow()
    }

    /// Evicts only when this exact directory is resident.
    func evict(directory: URL) {
        guard resident?.directory == directory else { return }
        evictNow()
    }

    private func scheduleEviction() {
        idleGeneration += 1
        let expected = idleGeneration
        Task {
            try? await Task.sleep(for: idleTimeout)
            guard expected == self.idleGeneration else { return }
            self.evictNow()
        }
    }
}

/// The app-wide MLX model cache. Loading takes seconds and ~2.5-3.5 GB of
/// unified memory, so the container stays resident after first use and is
/// freed after 5 idle minutes or when the engine choice changes.
nonisolated enum LocalModelRuntime {
    static let shared = ResidencyCache<ModelContainer>(
        idleTimeout: .seconds(300),
        onEvict: { MLX.GPU.clearCache() }
    ) { directory in
        guard FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("config.json").path) else {
            throw ModelFilesMissingError(directory: directory)
        }
        let container = try await LLMModelFactory.shared.loadContainer(
            from: directory, using: #huggingFaceTokenizerLoader())
        // Keep MLX's buffer pool from hoarding freed memory between requests.
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
        return container
    }
}
