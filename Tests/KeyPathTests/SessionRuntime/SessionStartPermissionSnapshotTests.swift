@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathPermissions
@preconcurrency import XCTest

/// Releases each requested permission snapshot only when the test says so.
private actor SnapshotGate {
    private var waiting: [CheckedContinuation<PermissionOracle.Snapshot, Never>] = []
    private(set) var requests = 0

    func next() async -> PermissionOracle.Snapshot {
        requests += 1
        return await withCheckedContinuation { waiting.append($0) }
    }

    func release(_ index: Int, _ snapshot: PermissionOracle.Snapshot) {
        waiting[index].resume(returning: snapshot)
    }
}

private func snapshot(runtimeReady: Bool) -> PermissionOracle.Snapshot {
    let granted = PermissionOracle.PermissionSet(
        accessibility: .granted, inputMonitoring: .granted,
        source: "test", confidence: .high, timestamp: Date()
    )
    let runtime = runtimeReady ? granted : PermissionOracle.PermissionSet(
        accessibility: .unknown, inputMonitoring: .unknown,
        source: "session-process-not-verified", confidence: .low, timestamp: Date()
    )
    return PermissionOracle.Snapshot(keyPath: granted, kanata: runtime, timestamp: Date(), backend: .session)
}

/// Launch on the Air (2026-10-18 10:19): a snapshot sampled before the worker
/// existed was served to validation after the worker was ready, so the overlay
/// showed a false blocking issue for a second after every successful start.
final class PermissionOracleInvalidationTests: XCTestCase {
    private func waitForRequests(_ gate: SnapshotGate, _ count: Int) async -> Bool {
        for _ in 0 ..< 10000 {
            if await gate.requests >= count { return true }
            await Task.yield()
        }
        return false
    }

    func testInvalidationNeitherSharesNorCachesASnapshotStartedBeforeIt() async {
        let oracle = PermissionOracle()
        let gate = SnapshotGate()
        await oracle.setTestSnapshotGenerator { await gate.next() }

        let beforeRuntime = Task { await oracle.currentSnapshot() }
        let firstRequested = await waitForRequests(gate, 1)
        XCTAssertTrue(firstRequested)
        await oracle.invalidateCache()

        let afterRuntime = Task { await oracle.currentSnapshot() }
        let secondRequested = await waitForRequests(gate, 2)
        XCTAssertTrue(secondRequested, "A caller after invalidation must not join the older computation")
        guard secondRequested else {
            await gate.release(0, snapshot(runtimeReady: true))
            _ = await beforeRuntime.value
            return
        }

        // The newer result lands first; the older one must not overwrite it.
        await gate.release(1, snapshot(runtimeReady: true))
        let afterResult = await afterRuntime.value
        XCTAssertTrue(afterResult.isSystemReady)
        await gate.release(0, snapshot(runtimeReady: false))
        _ = await beforeRuntime.value

        let cached = await oracle.currentSnapshot()
        XCTAssertTrue(cached.isSystemReady, "A pre-invalidation snapshot must not become the cached answer")
        let requests = await gate.requests
        XCTAssertEqual(requests, 2, "The fresh snapshot should still be served from cache")
    }
}

@MainActor
final class SessionStartPermissionSnapshotTests: KeyPathTestCase {
    func testSuccessfulSessionStartDiscardsPermissionSnapshotSampledBeforeIt() async {
        let coordinator = ServiceLifecycleCoordinator(
            kanataDaemonService: KanataDaemonService(),
            recoveryCoordinator: RecoveryCoordinator()
        )
        coordinator.testSessionConfigurationValidation = { .valid }
        let counter = SnapshotCounter()
        // Let the coordinator's own provider registration settle first.
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        await PermissionOracle.shared.setTestSnapshotGenerator {
            await counter.increment()
            return snapshot(runtimeReady: false)
        }
        addTeardownBlock { await PermissionOracle.shared.setTestSnapshotGenerator(nil) }

        _ = await SystemStateProvider.shared.currentPermissionSnapshot()
        _ = await SystemStateProvider.shared.currentPermissionSnapshot()
        let primed = await counter.count
        XCTAssertEqual(primed, 1, "Precondition: the pre-runtime snapshot is cached")

        ServiceLifecycleCoordinator.testSessionStart = { _ in true }
        defer { ServiceLifecycleCoordinator.testSessionStart = nil }
        let started = await coordinator.startKanata()
        XCTAssertTrue(started)

        _ = await SystemStateProvider.shared.currentPermissionSnapshot()
        let afterStart = await counter.count
        XCTAssertEqual(afterStart, 2, "Validation after a successful start must not reuse pre-runtime permissions")
    }
}

private actor SnapshotCounter {
    private(set) var count = 0
    func increment() {
        count += 1
    }
}
