import Foundation
import KeyPathCore
import ServiceManagement

/// Coalescing, off-actor reader of `SMAppService.status` (issue #853).
///
/// `SMAppService.status` is a **synchronous IPC** into `launchservicesd`. Under
/// concurrent load it can block the calling thread for 10–30s (see
/// `docs/bugs/2026-02-19-false-kanata-service-stopped-alert.md`). When that call
/// happens on the MainActor it stalls the whole app.
///
/// The only live registration is launch at login (`SMAppService.mainApp`, read by
/// `LaunchAtLoginController`). `SMAppServiceStatusLintTests` fails the build if any
/// other source references `SMAppService`'s `.status`.
///
/// ## Caching policy
///
/// - `cachedStatus(for:)` returns the cached value when it is younger than
///   `cacheTTL` (default 2s). On a miss it performs one fetch; concurrent misses
///   share a single in-flight `Task`.
/// - `freshStatus(for:)` always fetches and updates the cache. Use it for
///   one-shot correctness-critical flows such as a register/unregister.
///
/// Every fetch runs on a detached utility Task, so the blocking IPC never runs on
/// the caller's actor.
actor SMAppServiceStatusProvider {
    /// How long a cached status is served before a fresh fetch is required.
    ///
    /// Kept deliberately short: `.status` transitions (approval granted,
    /// registration completing) must surface quickly in the UI, but 2s is long
    /// enough to collapse a 250ms overlay-polling burst into a single IPC.
    private let cacheTTL: TimeInterval

    /// Fetches an `SMAppServiceProtocol` for a plist name. Injectable for tests so
    /// the provider can be exercised without touching real `launchservicesd` IPC.
    private let serviceFactory: @Sendable (String) -> SMAppServiceProtocol

    private struct CacheEntry {
        let status: SMAppService.Status
        let timestamp: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private var inFlight: [String: Task<SMAppService.Status, Never>] = [:]

    init(
        cacheTTL: TimeInterval = 2.0,
        serviceFactory: @escaping @Sendable (String) -> SMAppServiceProtocol
    ) {
        self.cacheTTL = cacheTTL
        self.serviceFactory = serviceFactory
    }

    // MARK: - Public accessors

    /// Cached status read: serves a value up to `cacheTTL` old, otherwise fetches.
    ///
    /// Concurrent misses for the same plist share one in-flight fetch. Safe for hot
    /// paths and polling loops.
    func cachedStatus(for plistName: String) async -> SMAppService.Status {
        if let entry = cache[plistName],
           Date().timeIntervalSince(entry.timestamp) < cacheTTL
        {
            return entry.status
        }
        return await refresh(plistName: plistName)
    }

    /// Uncached status read: always fetches, then updates the cache.
    ///
    /// Use on correctness-critical one-shot flows (install/unregister/uninstall)
    /// where a stale value is unacceptable. Still runs the IPC off the calling actor.
    func freshStatus(for plistName: String) async -> SMAppService.Status {
        await refresh(plistName: plistName)
    }

    /// Drop the cached value for a plist so the next read re-fetches. Call after a
    /// register/unregister so callers don't observe the pre-mutation status.
    func invalidate(plistName: String) {
        cache[plistName] = nil
    }

    /// Drop all cached values (e.g. after a full uninstall).
    func invalidateAll() {
        cache.removeAll()
    }

    // MARK: - Fetch + coalescing

    private func refresh(plistName: String) async -> SMAppService.Status {
        if let existing = inFlight[plistName] {
            return await existing.value
        }

        let factory = serviceFactory
        let task = Task<SMAppService.Status, Never>.detached(priority: .utility) {
            factory(plistName).status
        }
        inFlight[plistName] = task
        let status = await task.value
        inFlight[plistName] = nil
        cache[plistName] = CacheEntry(status: status, timestamp: Date())
        return status
    }
}
