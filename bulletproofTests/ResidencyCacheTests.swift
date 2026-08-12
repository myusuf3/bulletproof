import Foundation
import Synchronization
import Testing
@testable import bulletproof

/// Counts loads and can simulate failures; gate lets tests hold a load open.
private final class FakeLoader: Sendable {
    private let state = Mutex<(loads: Int, failNext: Bool)>((0, false))
    let gate = Mutex<CheckedContinuation<Void, Never>?>(nil)

    var loads: Int { state.withLock { $0.loads } }
    func failNext() { state.withLock { $0.failNext = true } }

    func load(_ directory: URL) async throws -> String {
        state.withLock { $0.loads += 1 }
        if state.withLock({ $0.failNext }) {
            state.withLock { $0.failNext = false }
            throw URLError(.cannotOpenFile)
        }
        return directory.lastPathComponent
    }
}

private let dirA = URL(fileURLWithPath: "/models/org/model-a")
private let dirB = URL(fileURLWithPath: "/models/org/model-b")

struct ResidencyCacheTests {
    private func makeCache(_ loader: FakeLoader,
                           idleTimeout: Duration = .seconds(10),
                           onEvict: @escaping @Sendable () -> Void = {}) -> ResidencyCache<String> {
        ResidencyCache(idleTimeout: idleTimeout, onEvict: onEvict) { try await loader.load($0) }
    }

    @Test func secondRequestIsCached() async throws {
        let loader = FakeLoader()
        let cache = makeCache(loader)
        _ = try await cache.resource(for: dirA)
        let second = try await cache.resource(for: dirA)
        #expect(second == "model-a")
        #expect(loader.loads == 1)
    }

    @Test func concurrentRequestsJoinOneLoad() async throws {
        let loader = FakeLoader()
        let cache = makeCache(loader)
        async let first = cache.resource(for: dirA)
        async let second = cache.resource(for: dirA)
        let results = try await [first, second]
        #expect(results == ["model-a", "model-a"])
        #expect(loader.loads == 1)
    }

    @Test func differentDirectoryEvictsAndReloads() async throws {
        let loader = FakeLoader()
        let evictions = Mutex(0)
        let cache = makeCache(loader) { evictions.withLock { $0 += 1 } }
        _ = try await cache.resource(for: dirA)
        let b = try await cache.resource(for: dirB)
        #expect(b == "model-b")
        #expect(loader.loads == 2)
        #expect(evictions.withLock { $0 } >= 1)
    }

    @Test func idleTimeoutEvicts() async throws {
        let loader = FakeLoader()
        let cache = makeCache(loader, idleTimeout: .milliseconds(30))
        _ = try await cache.resource(for: dirA)
        try await Task.sleep(for: .milliseconds(150))
        _ = try await cache.resource(for: dirA)
        #expect(loader.loads == 2)
    }

    @Test func touchResetsIdleClock() async throws {
        let loader = FakeLoader()
        let cache = makeCache(loader, idleTimeout: .milliseconds(200))
        _ = try await cache.resource(for: dirA)
        for _ in 0..<3 {
            try await Task.sleep(for: .milliseconds(80))
            await cache.touch()
        }
        _ = try await cache.resource(for: dirA)
        #expect(loader.loads == 1)
    }

    @Test func evictNowForcesReload() async throws {
        let loader = FakeLoader()
        let cache = makeCache(loader)
        _ = try await cache.resource(for: dirA)
        await cache.evictNow()
        _ = try await cache.resource(for: dirA)
        #expect(loader.loads == 2)
    }

    @Test func retainOnlyKeepsMatchingDirectory() async throws {
        let loader = FakeLoader()
        let cache = makeCache(loader)
        _ = try await cache.resource(for: dirA)
        await cache.retainOnly(dirA)
        _ = try await cache.resource(for: dirA)
        #expect(loader.loads == 1)
        await cache.retainOnly(nil)
        _ = try await cache.resource(for: dirA)
        #expect(loader.loads == 2)
    }

    @Test func targetedEvictOnlyDumpsThatDirectory() async throws {
        let loader = FakeLoader()
        let cache = makeCache(loader)
        _ = try await cache.resource(for: dirA)
        await cache.evict(directory: dirB)
        _ = try await cache.resource(for: dirA)
        #expect(loader.loads == 1)
        await cache.evict(directory: dirA)
        _ = try await cache.resource(for: dirA)
        #expect(loader.loads == 2)
    }

    @Test func failedLoadIsNotCached() async throws {
        let loader = FakeLoader()
        let cache = makeCache(loader)
        loader.failNext()
        await #expect(throws: URLError.self) {
            _ = try await cache.resource(for: dirA)
        }
        let recovered = try await cache.resource(for: dirA)
        #expect(recovered == "model-a")
        #expect(loader.loads == 2)
    }
}
