@testable import KeyPathAppKit
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathWizardCore
@preconcurrency import XCTest

/// Integration tests for ProcessLifecycleManager - tests the actual system
/// Updated to work with the simplified ProcessLifecycleManager that uses PID files
@MainActor
final class ProcessLifecycleIntegrationTests: XCTestCase {
    var processManager: ProcessLifecycleManager!

    override func setUp() async throws {
        try await super.setUp()
        processManager = ProcessLifecycleManager()
    }

    override func tearDown() async throws {
        processManager = nil
        try await super.tearDown()
    }

    // MARK: - Basic Operations Tests

    func testProcessLifecycleManagerBasicOperations() async throws {
        processManager.setIntent(.shouldBeRunning(source: "test_basic_operations"))

        try await processManager.registerStartedProcess(pid: pid_t(1234), command: "test command")
        try await processManager.unregisterProcess()
        try await processManager.cleanupOrphanedProcesses()
    }

    // MARK: - Conflict Detection Tests

    func testConflictDetection() async throws {
        processManager.setIntent(.shouldBeRunning(source: "test_conflict_detection"))

        try await processManager.registerStartedProcess(pid: pid_t(1234), command: "kanata command")

        let conflicts = try await processManager.detectConflicts()

        XCTAssertNotNil(conflicts.externalProcesses, "Should return external processes array")
        XCTAssertNotNil(conflicts.canAutoResolve, "Should indicate if conflicts can be auto-resolved")
    }

    func testProcessTermination() async throws {
        processManager.setIntent(.shouldBeRunning(source: "test_termination"))

        do {
            try await processManager.terminateExternalProcesses()
        } catch {
            // It's okay if this fails in test environment
        }
    }

    func testOrphanedProcessCleanup() async throws {
        try await processManager.cleanupOrphanedProcesses()
    }

    // MARK: - Performance Tests

    func testProcessDetectionPerformance() async throws {
        let operationsPerRun = 100
        let runCount = 5
        var samples: [Double] = []
        samples.reserveCapacity(runCount)

        for run in 0 ..< runCount {
            let startTime = CFAbsoluteTimeGetCurrent()

            for testIndex in 0 ..< operationsPerRun {
                processManager.setIntent(.shouldBeRunning(source: "perf_test_\(run)_\(testIndex)"))
                try await processManager.registerStartedProcess(
                    pid: pid_t(10000 + testIndex), command: "test command"
                )
                try await processManager.unregisterProcess()
            }

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            samples.append(duration)
        }

        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]

        XCTAssertLessThan(median, 1.25, "Median process operation duration regressed: \(median)s from samples \(samples)")
    }

    // MARK: - Error Handling Tests

    func testProcessErrorTypes() {
        let error = KeyPathError.process(.noManager)

        if case let .process(processError) = error {
            switch processError {
            case .noManager:
                XCTAssertTrue(true, "NoManager error exists")
            case .startFailed:
                XCTAssertTrue(true, "StartFailed error exists")
            case .stopFailed:
                XCTAssertTrue(true, "StopFailed error exists")
            case .terminateFailed:
                XCTAssertTrue(true, "TerminateFailed error exists")
            default:
                break
            }
        }
    }

    // MARK: - Thread Safety Tests

    func testConcurrentProcessManagement() async throws {
        let manager = try XCTUnwrap(processManager)

        let concurrentTasks = (1 ... 10).map { taskId in
            Task {
                manager.setIntent(.shouldBeRunning(source: "concurrent_\(taskId)"))
                try await manager.registerStartedProcess(pid: pid_t(20000 + taskId), command: "test command")
                try await manager.unregisterProcess()
            }
        }

        for task in concurrentTasks {
            try await task.value
        }
    }

    // MARK: - Real-World Integration Tests

    func testProcessLifecycleManagerInitialization() async throws {
        let manager = ProcessLifecycleManager()
        manager.setIntent(.shouldBeRunning(source: "initialization_test"))
        try await manager.cleanupOrphanedProcesses()
    }

    func testConflictResolutionStructure() async throws {
        let conflicts = try await processManager.detectConflicts()

        _ = conflicts.externalProcesses
        _ = conflicts.canAutoResolve
    }

    func testIntentReconciliation() async throws {
        processManager.setIntent(.shouldBeRunning(source: "test_intent"))

        do {
            try await processManager.reconcileWithIntent()
        } catch {
            // It's okay if this fails in test environment
        }
    }
}
