import Foundation
import KeyPathCore
import ServiceManagement

/// Single, centralized owner of `SMAppService.status` access (issue #853).
///
/// ## Why this exists
///
/// `SMAppService.status` is a **synchronous IPC** into `launchservicesd`. Under
/// concurrent load it can block the calling thread for 10–30s (see CLAUDE.md and
/// `docs/bugs/2026-02-19-false-kanata-service-stopped-alert.md`). When that call
/// happens on the MainActor — during UI init or a state-refresh tick — it stalls
/// the whole app.
///
/// Before this provider, `.status` was read directly from ~a dozen call sites
/// (App.swift fresh-install check, `KanataDaemonManager.getStatus()`,
/// `HelperMaintenance` unregister, wizard conformances, etc.). Each read was its
/// own uncoalesced IPC, so a burst of callers fanned out into parallel blocking
/// calls. `ServiceLifecycleCoordinator` had a private TTL cache, but only for the
/// one "pending" check it made — every other site bypassed it.
///
/// This provider is now the **only** place in the codebase that reads
/// `SMAppServiceProtocol.status`. `SMAppServiceStatusLintTests` fails the build if
/// any other source references `SMAppService`'s `.status`.
///
/// ## Caching policy
///
/// The provider keys a small in-memory cache by plist name (helper vs. kanata
/// daemon). Two access modes let callers pick their staleness tolerance:
///
/// - `cachedStatus(for:)` — returns the cached value when it is younger than
///   `cacheTTL` (default 2s). On a miss it performs one fetch; concurrent misses
///   for the same plist share a single in-flight `Task` so a polling burst never
///   fans out into parallel IPC. Use this on **hot paths** (UI init, state-refresh
///   ticks, overlay polling) where a value up to `cacheTTL` old is acceptable.
///
/// - `freshStatus(for:)` — bypasses the cache read, always performs a fetch, and
///   updates the cache with the result. Use this on **one-shot correctness-critical
///   flows** (install / unregister / uninstall) where a stale value could make the
///   flow skip or repeat a privileged operation. Even here the fetch still runs
///   off the calling actor, so it never blocks the MainActor.
///
/// Every fetch runs on a detached utility Task, so the blocking IPC happens on a
/// background executor and the actor (and any MainActor caller awaiting it) stays
/// responsive. Callers that mutate registration (register/unregister) should call
/// `invalidate(plistName:)` afterward so the next read re-fetches instead of
/// serving a value from before the mutation.
actor SMAppServiceStatusProvider {
    // Shared instance used by production call sites.
    //
    // In DEBUG this is a `var` so tests can substitute a provider backed by a fake
    // factory (and restore the original in teardown). Production keeps it immutable.
    #if DEBUG
        nonisolated(unsafe) static var shared = SMAppServiceStatusProvider()
    #else
        static let shared = SMAppServiceStatusProvider()
    #endif

    #if DEBUG
        /// Independent test seam for the legacy synchronous bridge. Tests that
        /// need both helper mutation and sync-status paths faked should set this
        /// explicitly or use HelperManager.smServiceFactory, whose didSet keeps
        /// this bridge aligned for helper approval checks.
        nonisolated(unsafe) static var synchronousServiceFactory: (String) -> SMAppServiceProtocol = { plistName in
            NativeSMAppService(wrapped: ServiceManagement.SMAppService.daemon(plistName: plistName))
        }
    #else
        static let synchronousServiceFactory: @Sendable (String) -> SMAppServiceProtocol = { plistName in
            NativeSMAppService(wrapped: ServiceManagement.SMAppService.daemon(plistName: plistName))
        }
    #endif

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
        serviceFactory: @escaping @Sendable (String) -> SMAppServiceProtocol = { plistName in
            NativeSMAppService(wrapped: ServiceManagement.SMAppService.daemon(plistName: plistName))
        }
    ) {
        self.cacheTTL = cacheTTL
        self.serviceFactory = serviceFactory
    }

    // MARK: - Public accessors

    /// Synchronous status read for legacy sync call sites that cannot yet await.
    ///
    /// Keep this bridge narrow. New code should prefer `cachedStatus(for:)` or
    /// `freshStatus(for:)` through `SystemStateProvider` so blocking IPC stays
    /// coalesced and off the caller's actor.
    nonisolated static func statusSynchronously(for plistName: String) -> SMAppService.Status {
        synchronousServiceFactory(plistName).status
    }

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
