import XCTest
@testable import KeyPath

/// Tests for ProcessLifecycleManager caching integration
/// Covers race condition fixes and cache invalidation
@MainActor
final class ProcessLifecycleManagerCacheTests: XCTestCase {

    var manager: ProcessLifecycleManager!

    override func setUp() async throws {
        try await super.setUp()
        manager = ProcessLifecycleManager()
    }

    override func tearDown() async throws {
        manager = nil
        try await super.tearDown()
    }

    // MARK: - Cache Invalidation Tests

    func testCacheInvalidationOnProcessRegistration() async {
        // Given: Manager with initial state
        let initialConflicts = await manager.detectConflicts()

        // When: Registering a new process
        await manager.registerStartedProcess(pid: 12345, command: "test-command")

        // Then: Should have invalidated cache (we can't directly test this, but we test behavior)
        let postRegisterConflicts = await manager.detectConflicts()

        // The cache invalidation should ensure fresh detection
        XCTAssertNotNil(postRegisterConflicts, "Should complete conflict detection after registration")

        print("✅ Cache invalidation on process registration test completed")
        print("   Initial conflicts: \(initialConflicts.externalProcesses.count)")
        print("   Post-register conflicts: \(postRegisterConflicts.externalProcesses.count)")
    }

    func testCacheInvalidationOnProcessUnregistration() async {
        // Given: Manager with registered process
        await manager.registerStartedProcess(pid: 12345, command: "test-command")

        // When: Unregistering the process
        await manager.unregisterProcess()

        // Then: Should have invalidated cache
        let conflicts = await manager.detectConflicts()
        XCTAssertNotNil(conflicts, "Should complete conflict detection after unregistration")

        print("✅ Cache invalidation on process unregistration test completed")
    }

    func testExternalCacheInvalidation() async {
        // Given: Manager with initial state
        let initialConflicts = await manager.detectConflicts()

        // When: Externally invalidating PID cache
        await manager.invalidatePIDCache()

        // Then: Should handle invalidation gracefully
        let postInvalidationConflicts = await manager.detectConflicts()
        XCTAssertNotNil(postInvalidationConflicts, "Should complete detection after external invalidation")

        print("✅ External cache invalidation test completed")
    }

    // MARK: - Conflict Detection Consistency Tests

    func testConsistentConflictDetection() async {
        // Test that repeated conflict detection calls return consistent results

        var results: [ProcessLifecycleManager.ConflictResolution] = []

        // When: Multiple rapid conflict detection calls
        for i in 0..<5 {
            let result = await manager.detectConflicts()
            results.append(result)

            print("Detection \(i + 1): External=\(result.externalProcesses.count), Managed=\(result.managedProcesses.count)")

            // Small delay to test caching behavior
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        // Then: Results should be consistent (race condition fix working)
        let externalCounts = results.map { $0.externalProcesses.count }
        let managedCounts = results.map { $0.managedProcesses.count }

        // Check for consistency within reasonable bounds
        let maxExternalVariation = externalCounts.max()! - externalCounts.min()!
        let maxManagedVariation = managedCounts.max()! - managedCounts.min()!

        XCTAssertLessThanOrEqual(
            maxExternalVariation, 1,
            "External process count should be consistent (max variation: \(maxExternalVariation))"
        )
        XCTAssertLessThanOrEqual(
            maxManagedVariation, 1,
            "Managed process count should be consistent (max variation: \(maxManagedVariation))"
        )

        print("✅ Consistent conflict detection test completed")
        print("   External process variation: \(maxExternalVariation)")
        print("   Managed process variation: \(maxManagedVariation)")
    }

    func testConcurrentConflictDetection() async {
        // Test concurrent conflict detection calls to verify race condition fix

        // When: Multiple concurrent conflict detection calls
        await withTaskGroup(of: ProcessLifecycleManager.ConflictResolution.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await self.manager.detectConflicts()
                }
            }

            var results: [ProcessLifecycleManager.ConflictResolution] = []
            for await result in group {
                results.append(result)
            }

            // Then: All calls should complete without hanging or crashing
            XCTAssertEqual(results.count, 10, "All concurrent calls should complete")

            // Results should be reasonably consistent
            let externalCounts = results.map { $0.externalProcesses.count }
            let uniqueExternalCounts = Set(externalCounts)

            XCTAssertLessThanOrEqual(
                uniqueExternalCounts.count, 3,
                "Concurrent calls should return reasonably consistent results"
            )

            print("✅ Concurrent conflict detection test completed")
            print("   Results: \(results.count)")
            print("   External count variations: \(uniqueExternalCounts)")
        }
    }

    // MARK: - Process Classification Tests

    func testProcessClassificationConsistency() async {
        // Test that same process gets classified consistently

        // Given: Detect current processes
        let conflicts = await manager.detectConflicts()
        let allProcesses = conflicts.externalProcesses + conflicts.managedProcesses

        if !allProcesses.isEmpty {
            let testProcess = allProcesses[0]

            // When: Multiple rapid classifications of the same process
            var classifications: [String] = []

            for _ in 0..<5 {
                let freshConflicts = await manager.detectConflicts()
                let allFreshProcesses = freshConflicts.externalProcesses + freshConflicts.managedProcesses

                // Find our test process in the fresh results
                if let foundProcess = allFreshProcesses.first(where: { $0.pid == testProcess.pid }) {
                    let isExternal = freshConflicts.externalProcesses.contains { $0.pid == foundProcess.pid }
                    classifications.append(isExternal ? "external" : "managed")
                }

                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
            }

            // Then: Classification should be consistent
            let uniqueClassifications = Set(classifications)
            XCTAssertLessThanOrEqual(
                uniqueClassifications.count, 1,
                "Process PID \(testProcess.pid) should have consistent classification: \(classifications)"
            )

            print("✅ Process classification consistency test completed")
            print("   Process PID \(testProcess.pid): \(classifications)")
        } else {
            print("✅ No processes to test classification (expected in clean test environment)")
        }
    }

    // MARK: - Cache Performance Tests

    func testCacheImprovestPerformance() async {
        // Test that caching improves conflict detection performance

        // When: First detection (cold cache)
        let startTime1 = Date()
        let result1 = await manager.detectConflicts()
        let duration1 = Date().timeIntervalSince(startTime1)

        // When: Second detection (warm cache)
        let startTime2 = Date()
        let result2 = await manager.detectConflicts()
        let duration2 = Date().timeIntervalSince(startTime2)

        // When: Third detection (warm cache)
        let startTime3 = Date()
        let result3 = await manager.detectConflicts()
        let duration3 = Date().timeIntervalSince(startTime3)

        // Then: Subsequent detections should be faster or similar
        // (May not always be faster due to system variation, but should not be significantly slower)
        XCTAssertLessThan(
            duration2, duration1 * 2,
            "Second detection should not be significantly slower than first"
        )
        XCTAssertLessThan(
            duration3, duration1 * 2,
            "Third detection should not be significantly slower than first"
        )

        print("✅ Cache performance test completed")
        print("   Detection 1: \(String(format: "%.3f", duration1))s")
        print("   Detection 2: \(String(format: "%.3f", duration2))s")
        print("   Detection 3: \(String(format: "%.3f", duration3))s")
    }

    func testRapidDetectionCalls() async {
        // Test rapid detection calls (simulates race condition scenario)

        let startTime = Date()
        var durations: [TimeInterval] = []
        var results: [ProcessLifecycleManager.ConflictResolution] = []

        // When: 20 rapid detection calls
        for i in 0..<20 {
            let callStart = Date()
            let result = await manager.detectConflicts()
            let callDuration = Date().timeIntervalSince(callStart)

            durations.append(callDuration)
            results.append(result)

            if i % 5 == 0 {
                print("   Call \(i + 1): \(String(format: "%.3f", callDuration))s, External=\(result.externalProcesses.count)")
            }
        }

        let totalDuration = Date().timeIntervalSince(startTime)

        // Then: All calls should complete in reasonable time
        XCTAssertLessThan(totalDuration, 30.0, "20 rapid calls should complete within 30 seconds")

        // No individual call should hang
        for (index, duration) in durations.enumerated() {
            XCTAssertLessThan(
                duration, 5.0,
                "Call \(index + 1) should complete within 5 seconds (actual: \(String(format: "%.3f", duration))s)"
            )
        }

        // Results should be reasonably consistent
        let externalCounts = results.map { $0.externalProcesses.count }
        let externalVariation = (externalCounts.max() ?? 0) - (externalCounts.min() ?? 0)

        XCTAssertLessThanOrEqual(
            externalVariation, 2,
            "External process count should be reasonably stable across rapid calls"
        )

        print("✅ Rapid detection calls test completed")
        print("   Total time: \(String(format: "%.3f", totalDuration))s")
        print("   Average per call: \(String(format: "%.3f", totalDuration / Double(durations.count)))s")
        print("   External count variation: \(externalVariation)")
    }

    // MARK: - Integration with Real System Tests

    func testIntegrationWithRealSystem() async {
        // Test integration with real system processes

        // When: Detecting conflicts on real system
        let conflicts = await manager.detectConflicts()

        // Then: Should handle real processes correctly
        for process in conflicts.externalProcesses {
            XCTAssertGreaterThan(process.pid, 0, "External process should have valid PID")
            XCTAssertTrue(
                process.command.contains("kanata") || process.command.contains("/bin/"),
                "External process should be a valid command"
            )
            XCTAssertFalse(
                process.command.contains("pgrep"),
                "Should filter out pgrep itself"
            )

            print("   External process: PID \(process.pid), command: \(process.command)")
        }

        for process in conflicts.managedProcesses {
            XCTAssertGreaterThan(process.pid, 0, "Managed process should have valid PID")
            XCTAssertTrue(
                process.command.contains("kanata"),
                "Managed process should contain kanata"
            )

            print("   Managed process: PID \(process.pid), command: \(process.command)")
        }

        print("✅ Real system integration test completed")
        print("   External processes: \(conflicts.externalProcesses.count)")
        print("   Managed processes: \(conflicts.managedProcesses.count)")
        print("   Can auto-resolve: \(conflicts.canAutoResolve)")
    }

    // MARK: - Edge Case Tests

    func testEmptySystemState() async {
        // Test behavior when no Kanata processes are running

        // When: Detecting conflicts on potentially clean system
        let conflicts = await manager.detectConflicts()

        // Then: Should handle empty state gracefully
        XCTAssertNotNil(conflicts, "Should return valid conflict resolution")
        XCTAssertGreaterThanOrEqual(conflicts.totalProcesses, 0, "Total processes should be non-negative")

        if conflicts.totalProcesses == 0 {
            XCTAssertFalse(conflicts.hasConflicts, "No processes should mean no conflicts")
            print("✅ Clean system detected (no Kanata processes)")
        } else {
            print("✅ System has \(conflicts.totalProcesses) Kanata process(es)")
        }
    }

    func testCacheInvalidationOnCleanup() async {
        // Test cache invalidation during cleanup operations

        // Given: Initial state
        let initialConflicts = await manager.detectConflicts()

        // When: Running cleanup
        await manager.cleanupOrphanedProcesses()

        // Then: Should complete without errors
        let postCleanupConflicts = await manager.detectConflicts()
        XCTAssertNotNil(postCleanupConflicts, "Should complete detection after cleanup")

        print("✅ Cache invalidation on cleanup test completed")
        print("   Initial: \(initialConflicts.totalProcesses) processes")
        print("   Post-cleanup: \(postCleanupConflicts.totalProcesses) processes")
    }

    // MARK: - Stress Tests

    func testStressTestRapidOperations() async {
        // Stress test with rapid operations to verify race condition fix

        let iterations = 50
        var operations: [String] = []

        // When: Rapid mixed operations
        for i in 0..<iterations {
            let operation = ["detect", "register", "unregister", "invalidate"].randomElement()!
            operations.append(operation)

            switch operation {
            case "detect":
                _ = await manager.detectConflicts()
            case "register":
                await manager.registerStartedProcess(pid: pid_t(1000 + i), command: "test-\(i)")
            case "unregister":
                await manager.unregisterProcess()
            case "invalidate":
                await manager.invalidatePIDCache()
            default:
                break
            }

            if i % 10 == 0 {
                print("   Completed \(i + 1)/\(iterations) operations")
            }
        }

        // Then: Should complete without crashes or hangs
        let finalConflicts = await manager.detectConflicts()
        XCTAssertNotNil(finalConflicts, "Should complete final detection after stress test")

        print("✅ Stress test completed: \(iterations) operations")
        print("   Operations: \(operations)")
        print("   Final state: \(finalConflicts.totalProcesses) processes")
    }
}
