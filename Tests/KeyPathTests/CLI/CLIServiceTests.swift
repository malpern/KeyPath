@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathInstallationWizard
@preconcurrency import XCTest

@MainActor
final class CLIServiceTests: XCTestCase {
    private let facade = SystemFacade()

    // MARK: - serviceLogs

    func testServiceLogsReturnsEmptyForMissingFile() {
        let lines = facade.serviceLogs(lines: 10)
        // If the log file doesn't exist in the test environment, we get empty
        // If it does exist, we get some lines. Either way, no crash.
        XCTAssertTrue(lines.count <= 10)
    }

    func testServiceLogsRespectsLineLimit() {
        let lines = facade.serviceLogs(lines: 5)
        XCTAssertTrue(lines.count <= 5)
    }

    func testServiceLogsDefaultsTo50Lines() {
        let lines = facade.serviceLogs()
        XCTAssertTrue(lines.count <= 50)
    }

    // MARK: - service lifecycle

    func testStopServiceReturnsFalseWhenPrivilegedHelperFails() async {
        let facade = SystemFacade(
            stopServiceOperation: { throw ServiceOperationError.failed },
            runtimeSnapshotProvider: { Self.runtimeSnapshot(running: true, responding: true) },
            runtimeTransitionTimeoutSeconds: 0.05,
            pollDelayNanoseconds: 0
        )

        let stopped = await facade.stopService()

        XCTAssertFalse(stopped)
    }

    func testStopServiceWaitsForStoppedRuntimeAfterHelperSuccess() async {
        let snapshots = RuntimeSnapshotSequence([
            Self.runtimeSnapshot(running: true, responding: true),
            Self.runtimeSnapshot(running: false, responding: false)
        ])
        let operations = ServiceOperationRecorder()

        let facade = SystemFacade(
            stopServiceOperation: { await operations.recordStop() },
            runtimeSnapshotProvider: { await snapshots.next() },
            runtimeTransitionTimeoutSeconds: 0.05,
            pollDelayNanoseconds: 0
        )

        let stopped = await facade.stopService()
        let stopCount = await operations.stopCount

        XCTAssertTrue(stopped)
        XCTAssertEqual(stopCount, 1)
    }

    func testRestartServiceDoesNotReportSuccessWhenStopFails() async {
        let operations = ServiceOperationRecorder()

        let facade = SystemFacade(
            startServiceOperation: { await operations.recordStart() },
            stopServiceOperation: { throw ServiceOperationError.failed },
            runtimeSnapshotProvider: { Self.runtimeSnapshot(running: true, responding: true) },
            runtimeTransitionTimeoutSeconds: 0.05,
            pollDelayNanoseconds: 0,
            restartDelayNanoseconds: 0
        )

        let restarted = await facade.restartService()
        let startCount = await operations.startCount

        XCTAssertFalse(restarted)
        XCTAssertEqual(startCount, 0)
    }

    func testStartServiceReturnsFalseWhenRuntimeNeverBecomesHealthy() async {
        let facade = SystemFacade(
            startServiceOperation: {},
            runtimeSnapshotProvider: { Self.runtimeSnapshot(running: true, responding: false) },
            runtimeTransitionTimeoutSeconds: 0.05,
            pollDelayNanoseconds: 0
        )

        let started = await facade.startService()

        XCTAssertFalse(started)
    }

    func testStartServiceWaitsForHealthyRuntimeAfterHelperSuccess() async {
        let snapshots = RuntimeSnapshotSequence([
            Self.runtimeSnapshot(running: false, responding: false),
            Self.runtimeSnapshot(running: true, responding: true)
        ])
        let operations = ServiceOperationRecorder()
        let facade = SystemFacade(
            startServiceOperation: { await operations.recordStart() },
            runtimeSnapshotProvider: { await snapshots.next() },
            runtimeTransitionTimeoutSeconds: 0.05,
            pollDelayNanoseconds: 0
        )

        let started = await facade.startService()
        let startCount = await operations.startCount

        XCTAssertTrue(started)
        XCTAssertEqual(startCount, 1)
    }

    func testServiceOperationsInvalidateRuntimeHealthCacheBeforePolling() async {
        let invalidations = SynchronousCallRecorder()
        let stoppedFacade = SystemFacade(
            stopServiceOperation: {},
            runtimeCacheInvalidator: { invalidations.record() },
            runtimeSnapshotProvider: { Self.runtimeSnapshot(running: false, responding: false) },
            runtimeTransitionTimeoutSeconds: 0.05,
            pollDelayNanoseconds: 0
        )
        let startedFacade = SystemFacade(
            startServiceOperation: {},
            runtimeCacheInvalidator: { invalidations.record() },
            runtimeSnapshotProvider: { Self.runtimeSnapshot(running: true, responding: true) },
            runtimeTransitionTimeoutSeconds: 0.05,
            pollDelayNanoseconds: 0
        )

        let stopped = await stoppedFacade.stopService()
        let started = await startedFacade.startService()

        XCTAssertTrue(stopped)
        XCTAssertTrue(started)
        XCTAssertEqual(invalidations.count, 2)
    }

    private nonisolated static func runtimeSnapshot(
        running: Bool,
        responding: Bool
    ) -> ServiceHealthChecker.KanataServiceRuntimeSnapshot {
        ServiceHealthChecker.KanataServiceRuntimeSnapshot(
            managementState: .smappserviceActive,
            isRunning: running,
            isResponding: responding,
            inputCaptureReady: true,
            inputCaptureIssue: nil,
            launchctlExitCode: running ? 0 : nil,
            staleEnabledRegistration: false,
            recentlyRestarted: false
        )
    }
}

private enum ServiceOperationError: Error {
    case failed
}

private actor ServiceOperationRecorder {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func recordStart() {
        startCount += 1
    }

    func recordStop() {
        stopCount += 1
    }
}

private final class SynchronousCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCount = 0

    var count: Int {
        lock.withLock { recordedCount }
    }

    func record() {
        lock.withLock { recordedCount += 1 }
    }
}

private actor RuntimeSnapshotSequence {
    private var snapshots: [ServiceHealthChecker.KanataServiceRuntimeSnapshot]

    init(_ snapshots: [ServiceHealthChecker.KanataServiceRuntimeSnapshot]) {
        self.snapshots = snapshots
    }

    func next() -> ServiceHealthChecker.KanataServiceRuntimeSnapshot {
        if snapshots.count > 1 {
            return snapshots.removeFirst()
        }
        return snapshots[0]
    }
}
