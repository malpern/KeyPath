@testable import KeyPathAppKit
import ServiceManagement
@preconcurrency import XCTest

/// Unit tests for the centralized `SMAppServiceStatusProvider` (issue #853):
/// verifies TTL caching, in-flight coalescing, fresh reads, and invalidation.
final class SMAppServiceStatusProviderTests: XCTestCase {
    /// Counts how many times `.status` is actually read, so tests can assert the
    /// provider collapses reads instead of fanning out into IPC.
    private final class CountingService: SMAppServiceProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var _statusReads = 0
        private var _status: SMAppService.Status

        init(status: SMAppService.Status) {
            _status = status
        }

        var statusReads: Int {
            lock.withLock { _statusReads }
        }

        func setStatus(_ new: SMAppService.Status) {
            lock.withLock { _status = new }
        }

        var status: SMAppService.Status {
            lock.withLock {
                _statusReads += 1
                return _status
            }
        }

        func register() throws {}
        func unregister() async throws {}
    }

    private func makeProvider(
        service: CountingService,
        cacheTTL: TimeInterval
    ) -> SMAppServiceStatusProvider {
        SMAppServiceStatusProvider(cacheTTL: cacheTTL, serviceFactory: { _ in service })
    }

    func testCachedStatusServesFromCacheWithinTTL() async {
        let service = CountingService(status: .enabled)
        let provider = makeProvider(service: service, cacheTTL: 60)

        let first = await provider.cachedStatus(for: "test.plist")
        let second = await provider.cachedStatus(for: "test.plist")

        XCTAssertEqual(first, .enabled)
        XCTAssertEqual(second, .enabled)
        XCTAssertEqual(service.statusReads, 1, "Second read within TTL should be served from cache")
    }

    func testCachedStatusRefetchesAfterTTLExpiry() async {
        let service = CountingService(status: .enabled)
        let provider = makeProvider(service: service, cacheTTL: 0)

        _ = await provider.cachedStatus(for: "test.plist")
        service.setStatus(.notRegistered)
        let second = await provider.cachedStatus(for: "test.plist")

        XCTAssertEqual(second, .notRegistered, "Zero TTL should force a re-fetch")
        XCTAssertEqual(service.statusReads, 2)
    }

    func testFreshStatusAlwaysRefetches() async {
        let service = CountingService(status: .enabled)
        let provider = makeProvider(service: service, cacheTTL: 60)

        _ = await provider.freshStatus(for: "test.plist")
        _ = await provider.freshStatus(for: "test.plist")

        XCTAssertEqual(service.statusReads, 2, "freshStatus must bypass the cache read every time")
    }

    func testFreshStatusPrimesCacheForSubsequentCachedRead() async {
        let service = CountingService(status: .requiresApproval)
        let provider = makeProvider(service: service, cacheTTL: 60)

        let fresh = await provider.freshStatus(for: "test.plist")
        let cached = await provider.cachedStatus(for: "test.plist")

        XCTAssertEqual(fresh, .requiresApproval)
        XCTAssertEqual(cached, .requiresApproval)
        XCTAssertEqual(service.statusReads, 1, "fresh read should populate the cache the cached read then reuses")
    }

    func testInvalidateForcesRefetch() async {
        let service = CountingService(status: .enabled)
        let provider = makeProvider(service: service, cacheTTL: 60)

        _ = await provider.cachedStatus(for: "test.plist")
        await provider.invalidate(plistName: "test.plist")
        service.setStatus(.notRegistered)
        let afterInvalidate = await provider.cachedStatus(for: "test.plist")

        XCTAssertEqual(afterInvalidate, .notRegistered)
        XCTAssertEqual(service.statusReads, 2)
    }

    func testConcurrentMissesCoalesceIntoSingleFetch() async {
        let service = CountingService(status: .enabled)
        let provider = makeProvider(service: service, cacheTTL: 60)

        // Fire many concurrent reads against a cold cache; they should share one fetch.
        await withTaskGroup(of: SMAppService.Status.self) { group in
            for _ in 0 ..< 32 {
                group.addTask { await provider.cachedStatus(for: "test.plist") }
            }
            for await value in group {
                XCTAssertEqual(value, .enabled)
            }
        }

        XCTAssertEqual(
            service.statusReads, 1,
            "Concurrent cold-cache reads must coalesce into a single underlying status read"
        )
    }

    func testDistinctPlistsAreCachedIndependently() async {
        let helper = CountingService(status: .enabled)
        let daemon = CountingService(status: .requiresApproval)
        let provider = SMAppServiceStatusProvider(cacheTTL: 60, serviceFactory: { plist in
            plist == "helper.plist" ? helper : daemon
        })

        let helperStatus = await provider.cachedStatus(for: "helper.plist")
        let daemonStatus = await provider.cachedStatus(for: "daemon.plist")

        XCTAssertEqual(helperStatus, .enabled)
        XCTAssertEqual(daemonStatus, .requiresApproval)
    }
}
