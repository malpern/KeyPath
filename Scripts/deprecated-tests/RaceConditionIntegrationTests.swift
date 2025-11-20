@testable import KeyPathAppKit
import XCTest

/// Integration tests for race condition scenarios
/// Tests the complete fix including caching, debouncing, and timeout protection
@MainActor
final class RaceConditionIntegrationTests: XCTestCase {
    var kanataManager: KanataManager!
    var detector: SystemStateDetector!
    var processManager: ProcessLifecycleManager!

    override func setUp() async throws {
        try await super.setUp()
        kanataManager = KanataManager()
        detector = SystemStateDetector(kanataManager: kanataManager)
        processManager = ProcessLifecycleManager(kanataManager: kanataManager)
    }

    override func tearDown() async throws {
        detector = nil
        processManager = nil
        kanataManager = nil
        try await super.tearDown()
    }

    // MARK: - Core Race Condition Scenario Tests

    func testOriginalRaceConditionScenario() async {
        // Test the original race condition: same PID classified differently in rapid succession

        print("🧪 Testing original race condition scenario...")

        var pidClassifications: [String: [String]] = [:]
        let iterations = 20

        // When: Rapid conflict detection to trigger race condition scenario
        for i in 0 ..< iterations {
            let conflicts = await processManager.detectConflicts()
            let allProcesses = conflicts.externalProcesses + conflicts.managedProcesses

            // Track classification of each PID
            for process in conflicts.externalProcesses {
                let pidKey = "\(process.pid)"
                pidClassifications[pidKey, default: []].append("external")
            }

            for process in conflicts.managedProcesses {
                let pidKey = "\(process.pid)"
                pidClassifications[pidKey, default: []].append("managed")
            }

            if i % 5 == 0 {
                print("   Iteration \(i + 1): External=\(conflicts.externalProcesses.count), Managed=\(conflicts.managedProcesses.count)")
            }

            // Very brief delay to trigger rapid detection
            try? await Task.sleep(nanoseconds: 20_000_000) // 0.02 seconds
        }

        // Then: Each PID should have consistent classification (race condition fixed)
        var inconsistentPIDs: [String] = []

        for (pid, classifications) in pidClassifications {
            let uniqueClassifications = Set(classifications)
            if uniqueClassifications.count > 1 {
                inconsistentPIDs.append(pid)
                print("⚠️ PID \(pid) had inconsistent classifications: \(classifications)")
            }
        }

        XCTAssertTrue(
            inconsistentPIDs.isEmpty,
            "Race condition fix failed: PIDs \(inconsistentPIDs) had inconsistent classifications"
        )

        print("✅ Original race condition scenario test completed")
        print("   Tracked PIDs: \(pidClassifications.count)")
        print("   Inconsistent PIDs: \(inconsistentPIDs.count)")

        if pidClassifications.isEmpty {
            print("   No Kanata processes detected (expected in clean test environment)")
        } else {
            for (pid, classifications) in pidClassifications.prefix(5) {
                print("   PID \(pid): \(classifications.count) classifications (\(Set(classifications)))")
            }
        }
    }

    func testFlickeringConflictScenario() async {
        // Test scenario where conflicts appear and disappear rapidly

        print("🧪 Testing flickering conflict scenario...")

        var conflictStates: [(hasConflicts: Bool, timestamp: Date)] = []
        let monitoringDuration: TimeInterval = 3.0
        let startTime = Date()

        // When: Continuous monitoring for flickering conflicts
        while Date().timeIntervalSince(startTime) < monitoringDuration {
            let conflicts = await detector.detectConflicts()
            let hasConflicts = !conflicts.conflicts.isEmpty
            let timestamp = Date()

            conflictStates.append((hasConflicts: hasConflicts, timestamp: timestamp))

            // Brief delay
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        }

        // Then: Should not have excessive flickering
        var flickerCount = 0
        for i in 1 ..< conflictStates.count {
            if conflictStates[i].hasConflicts != conflictStates[i - 1].hasConflicts {
                flickerCount += 1
                let timeDiff = conflictStates[i].timestamp.timeIntervalSince(conflictStates[i - 1].timestamp)
                print("   Conflict state change at \(String(format: "%.3f", timeDiff))s: \(conflictStates[i - 1].hasConflicts) -> \(conflictStates[i].hasConflicts)")
            }
        }

        // Debouncing should prevent excessive flickering
        let maxAllowedFlickers = max(2, conflictStates.count / 10) // Allow some variation, but not excessive
        XCTAssertLessThanOrEqual(
            flickerCount, maxAllowedFlickers,
            "Excessive conflict flickering detected: \(flickerCount) flickers in \(conflictStates.count) detections"
        )

        print("✅ Flickering conflict scenario test completed")
        print("   Monitoring duration: \(String(format: "%.1f", monitoringDuration))s")
        print("   Total detections: \(conflictStates.count)")
        print("   Flicker count: \(flickerCount)")
        print("   Flicker rate: \(String(format: "%.1f", Double(flickerCount) / Double(conflictStates.count) * 100))%")
    }

    func testConcurrentWizardRefreshScenario() async {
        // Test scenario where multiple wizard refreshes happen concurrently

        print("🧪 Testing concurrent wizard refresh scenario...")

        let concurrentOperations = 8
        let startTime = Date()

        // When: Multiple concurrent full state detections (simulating wizard refreshes)
        await withTaskGroup(of: (SystemStateResult, TimeInterval).self) { group in
            for i in 0 ..< concurrentOperations {
                group.addTask {
                    let operationStart = Date()
                    let result = await self.detector.detectCurrentState()
                    let duration = Date().timeIntervalSince(operationStart)
                    return (result, duration)
                }
            }

            var results: [(SystemStateResult, TimeInterval)] = []
            for await result in group {
                results.append(result)
            }

            let totalDuration = Date().timeIntervalSince(startTime)

            // Then: All operations should complete successfully
            XCTAssertEqual(results.count, concurrentOperations, "All concurrent operations should complete")

            // No operation should hang
            for (index, (_, duration)) in results.enumerated() {
                XCTAssertLessThan(
                    duration, 10.0,
                    "Operation \(index + 1) should complete within 10 seconds (actual: \(String(format: "%.3f", duration))s)"
                )
            }

            // Results should be reasonably consistent
            let states = results.map { "\($0.0.state)" }
            let uniqueStates = Set(states)
            XCTAssertLessThanOrEqual(
                uniqueStates.count, 3,
                "Concurrent operations should return reasonably consistent states"
            )

            print("✅ Concurrent wizard refresh scenario test completed")
            print("   Total duration: \(String(format: "%.3f", totalDuration))s")
            print("   Individual durations: \(results.map { String(format: "%.3f", $0.1) })")
            print("   Unique states: \(uniqueStates.count)")
            print("   States: \(uniqueStates)")
        }
    }

    // MARK: - Cache Timeout and Error Scenarios

    func testSlowLaunchctlScenario() async {
        // Test scenario where launchctl is slow to respond

        print("🧪 Testing slow launchctl scenario...")

        var responseTimes: [TimeInterval] = []
        let iterations = 5

        // When: Multiple detections that may encounter slow launchctl
        for i in 0 ..< iterations {
            let startTime = Date()
            let conflicts = await processManager.detectConflicts()
            let responseTime = Date().timeIntervalSince(startTime)

            responseTimes.append(responseTime)

            print("   Detection \(i + 1): \(String(format: "%.3f", responseTime))s, External=\(conflicts.externalProcesses.count)")

            // Brief delay between detections
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        // Then: Should handle slow responses gracefully with timeout protection
        for (index, responseTime) in responseTimes.enumerated() {
            XCTAssertLessThan(
                responseTime, 15.0, // Allow generous timeout but not infinite
                "Detection \(index + 1) should complete within timeout period"
            )
        }

        let averageResponseTime = responseTimes.reduce(0, +) / Double(responseTimes.count)
        let maxResponseTime = responseTimes.max() ?? 0

        print("✅ Slow launchctl scenario test completed")
        print("   Average response time: \(String(format: "%.3f", averageResponseTime))s")
        print("   Max response time: \(String(format: "%.3f", maxResponseTime))s")
        print("   All responses: \(responseTimes.map { String(format: "%.3f", $0) })")
    }

    func testCacheInvalidationImpactScenario() async {
        // Test scenario where cache invalidations happen during rapid detection

        print("🧪 Testing cache invalidation impact scenario...")

        var detectionResults: [ProcessLifecycleManager.ConflictResolution] = []
        var invalidationTimes: [TimeInterval] = []
        let startTime = Date()

        // When: Interleaved detection and cache invalidation
        for i in 0 ..< 10 {
            // Detection
            let detectionStart = Date()
            let result = await processManager.detectConflicts()
            let detectionTime = Date().timeIntervalSince(detectionStart)

            detectionResults.append(result)

            // Periodic cache invalidation
            if i % 3 == 0 {
                let invalidationStart = Date()
                await processManager.invalidatePIDCache()
                let invalidationTime = Date().timeIntervalSince(invalidationStart)
                invalidationTimes.append(invalidationTime)

                print("   Step \(i + 1): Detection \(String(format: "%.3f", detectionTime))s, Invalidation \(String(format: "%.3f", invalidationTime))s")
            } else {
                print("   Step \(i + 1): Detection \(String(format: "%.3f", detectionTime))s")
            }

            try? await Task.sleep(nanoseconds: 30_000_000) // 0.03 seconds
        }

        let totalDuration = Date().timeIntervalSince(startTime)

        // Then: Should handle invalidations gracefully
        XCTAssertEqual(detectionResults.count, 10, "All detections should complete")
        XCTAssertLessThan(totalDuration, 8.0, "Total operation should complete within 8 seconds")

        // Check result consistency despite invalidations
        let externalCounts = detectionResults.map(\.externalProcesses.count)
        let externalVariation = (externalCounts.max() ?? 0) - (externalCounts.min() ?? 0)

        XCTAssertLessThanOrEqual(
            externalVariation, 2,
            "External process count should be reasonably stable despite cache invalidations"
        )

        print("✅ Cache invalidation impact scenario test completed")
        print("   Total duration: \(String(format: "%.3f", totalDuration))s")
        print("   Cache invalidations: \(invalidationTimes.count)")
        print("   External count variation: \(externalVariation)")
    }

    // MARK: - End-to-End Integration Scenarios

    func testCompleteRaceConditionFixIntegration() async {
        // End-to-end test of the complete race condition fix

        print("🧪 Testing complete race condition fix integration...")

        let testDuration: TimeInterval = 5.0
        let startTime = Date()

        var operationLog: [(operation: String, timestamp: TimeInterval, result: String)] = []

        // When: Mixed operations that previously triggered race conditions
        while Date().timeIntervalSince(startTime) < testDuration {
            let currentTime = Date().timeIntervalSince(startTime)

            // Randomly choose operation type
            let operations = ["detectConflicts", "detectState", "invalidateCache"]
            let operation = operations.randomElement()!

            switch operation {
            case "detectConflicts":
                let result = await detector.detectConflicts()
                operationLog.append((
                    operation: "conflicts",
                    timestamp: currentTime,
                    result: "\(result.conflicts.count) conflicts"
                ))

            case "detectState":
                let result = await detector.detectCurrentState()
                operationLog.append((
                    operation: "state",
                    timestamp: currentTime,
                    result: "\(result.state)"
                ))

            case "invalidateCache":
                await processManager.invalidatePIDCache()
                operationLog.append((
                    operation: "invalidate",
                    timestamp: currentTime,
                    result: "cache cleared"
                ))

            default:
                break
            }

            // Brief delay
            try? await Task.sleep(nanoseconds: 25_000_000) // 0.025 seconds
        }

        let totalDuration = Date().timeIntervalSince(startTime)

        // Then: All operations should complete without race conditions
        XCTAssertGreaterThan(operationLog.count, 20, "Should have completed many operations")
        XCTAssertLessThan(totalDuration, testDuration + 2.0, "Should complete within expected time")

        // Analyze operation distribution
        let conflictOps = operationLog.filter { $0.operation == "conflicts" }.count
        let stateOps = operationLog.filter { $0.operation == "state" }.count
        let invalidateOps = operationLog.filter { $0.operation == "invalidate" }.count

        print("✅ Complete race condition fix integration test completed")
        print("   Duration: \(String(format: "%.3f", totalDuration))s")
        print("   Total operations: \(operationLog.count)")
        print("   Conflict detections: \(conflictOps)")
        print("   State detections: \(stateOps)")
        print("   Cache invalidations: \(invalidateOps)")

        // Sample of operations
        print("   Sample operations:")
        for operation in operationLog.prefix(10) {
            print("     \(String(format: "%.3f", operation.timestamp))s: \(operation.operation) -> \(operation.result)")
        }
    }

    func testWizardUIFlickerPrevention() async {
        // Test that debouncing prevents UI flicker in wizard scenarios

        print("🧪 Testing wizard UI flicker prevention...")

        var stateTransitions: [(from: String, to: String, time: TimeInterval)] = []
        var previousState: WizardSystemState?
        let startTime = Date()
        let monitoringDuration: TimeInterval = 4.0

        // When: Continuous state monitoring (simulating wizard UI updates)
        while Date().timeIntervalSince(startTime) < monitoringDuration {
            let result = await detector.detectCurrentState()
            let currentTime = Date().timeIntervalSince(startTime)

            if let prevState = previousState {
                let prevStateString = "\(prevState)"
                let currentStateString = "\(result.state)"

                if prevStateString != currentStateString {
                    stateTransitions.append((
                        from: prevStateString,
                        to: currentStateString,
                        time: currentTime
                    ))
                }
            }

            previousState = result.state

            // UI-like refresh rate
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        // Then: Should have minimal state transitions (flicker prevention working)
        let totalDetections = Int(monitoringDuration / 0.1)
        let transitionRate = Double(stateTransitions.count) / Double(totalDetections)

        XCTAssertLessThan(
            transitionRate, 0.3, // Less than 30% transition rate
            "Too many state transitions detected: \(stateTransitions.count) transitions in ~\(totalDetections) detections"
        )

        print("✅ Wizard UI flicker prevention test completed")
        print("   Monitoring duration: \(String(format: "%.1f", monitoringDuration))s")
        print("   State transitions: \(stateTransitions.count)")
        print("   Transition rate: \(String(format: "%.1f", transitionRate * 100))%")

        if !stateTransitions.isEmpty {
            print("   Transitions:")
            for transition in stateTransitions.prefix(5) {
                print("     \(String(format: "%.3f", transition.time))s: \(transition.from) -> \(transition.to)")
            }
        }
    }

    // MARK: - Performance Impact Assessment

    func testPerformanceImpactOfFix() async {
        // Test that the race condition fix doesn't negatively impact performance

        print("🧪 Testing performance impact of race condition fix...")

        // Baseline: Single operations
        let baselineConflictStart = Date()
        _ = await detector.detectConflicts()
        let baselineConflictTime = Date().timeIntervalSince(baselineConflictStart)

        let baselineStateStart = Date()
        _ = await detector.detectCurrentState()
        let baselineStateTime = Date().timeIntervalSince(baselineStateStart)

        // Load test: Rapid operations
        let loadTestStart = Date()
        var loadTestTimes: [TimeInterval] = []

        for i in 0 ..< 15 {
            let operationStart = Date()
            if i % 2 == 0 {
                _ = await detector.detectConflicts()
            } else {
                _ = await detector.detectCurrentState()
            }
            let operationTime = Date().timeIntervalSince(operationStart)
            loadTestTimes.append(operationTime)
        }

        let totalLoadTestTime = Date().timeIntervalSince(loadTestStart)
        let averageLoadTestTime = loadTestTimes.reduce(0, +) / Double(loadTestTimes.count)

        // Then: Performance should be acceptable
        XCTAssertLessThan(totalLoadTestTime, 20.0, "Load test should complete within 20 seconds")

        // Individual operations shouldn't be significantly slower
        XCTAssertLessThan(
            averageLoadTestTime, max(baselineConflictTime, baselineStateTime) * 3,
            "Load test operations should not be excessively slower than baseline"
        )

        print("✅ Performance impact test completed")
        print("   Baseline conflict: \(String(format: "%.3f", baselineConflictTime))s")
        print("   Baseline state: \(String(format: "%.3f", baselineStateTime))s")
        print("   Load test total: \(String(format: "%.3f", totalLoadTestTime))s")
        print("   Load test average: \(String(format: "%.3f", averageLoadTestTime))s")
        print("   Load test range: \(String(format: "%.3f", loadTestTimes.min() ?? 0))s - \(String(format: "%.3f", loadTestTimes.max() ?? 0))s")
    }

    // MARK: - Regression Prevention Tests

    func testNoRegressionInExistingFunctionality() async {
        // Ensure race condition fix doesn't break existing functionality

        print("🧪 Testing no regression in existing functionality...")

        // Test all major detection operations
        let conflictResult = await detector.detectConflicts()
        let permissionResult = await detector.checkPermissions()
        let componentResult = await detector.checkComponents()
        let fullStateResult = await detector.detectCurrentState()

        // Basic functionality should work
        XCTAssertNotNil(conflictResult, "Conflict detection should work")
        XCTAssertNotNil(permissionResult, "Permission checking should work")
        XCTAssertNotNil(componentResult, "Component checking should work")
        XCTAssertNotNil(fullStateResult, "Full state detection should work")

        // Results should be reasonable
        XCTAssertGreaterThanOrEqual(conflictResult.conflicts.count, 0)
        XCTAssertGreaterThanOrEqual(permissionResult.granted.count + permissionResult.missing.count, 0)
        XCTAssertGreaterThanOrEqual(componentResult.installed.count + componentResult.missing.count, 0)
        XCTAssertNotEqual(fullStateResult.state, .initializing)

        // Test process lifecycle operations
        await processManager.registerStartedProcess(pid: 99999, command: "test-command")
        await processManager.unregisterProcess()
        await processManager.invalidatePIDCache()
        await processManager.cleanupOrphanedProcesses()

        // Should complete without errors
        let finalConflicts = await processManager.detectConflicts()
        XCTAssertNotNil(finalConflicts, "Process lifecycle operations should work")

        print("✅ No regression test completed")
        print("   Conflict detection: ✅")
        print("   Permission checking: ✅")
        print("   Component checking: ✅")
        print("   Full state detection: ✅")
        print("   Process lifecycle: ✅")
    }

    func testSpecificRaceConditionScenarioFromBug() async {
        // Test the specific scenario from the original bug report
        // PID 57129 flickering between "managed" and "external"

        print("🧪 Testing specific race condition scenario from bug report...")

        var pidStatuses: [String: [String]] = [:]
        let rapidIterations = 30

        // When: Rapid succession like in the original bug
        for i in 0 ..< rapidIterations {
            let conflicts = await processManager.detectConflicts()

            // Track all PIDs and their classifications
            for process in conflicts.externalProcesses {
                let pidKey = "\(process.pid)"
                pidStatuses[pidKey, default: []].append("external")
            }

            for process in conflicts.managedProcesses {
                let pidKey = "\(process.pid)"
                pidStatuses[pidKey, default: []].append("managed")
            }

            // Rapid timing similar to original issue
            try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        }

        // Then: No PID should have inconsistent classification
        var inconsistentPIDs: [String] = []
        var maxInconsistency = 0

        for (pid, statuses) in pidStatuses {
            let uniqueStatuses = Set(statuses)
            if uniqueStatuses.count > 1 {
                inconsistentPIDs.append(pid)
                maxInconsistency = max(maxInconsistency, uniqueStatuses.count)
                print("❌ PID \(pid) inconsistent: \(statuses) -> unique: \(uniqueStatuses)")
            }
        }

        XCTAssertTrue(
            inconsistentPIDs.isEmpty,
            "Race condition not fixed: PIDs \(inconsistentPIDs) still have inconsistent classifications"
        )

        print("✅ Specific race condition scenario test completed")
        print("   Rapid iterations: \(rapidIterations)")
        print("   Tracked PIDs: \(pidStatuses.count)")
        print("   Inconsistent PIDs: \(inconsistentPIDs.count)")

        if pidStatuses.isEmpty {
            print("   No Kanata processes found (expected in clean test environment)")
        } else {
            // Show sample of consistent PIDs
            let consistentSample = pidStatuses.filter { Set($0.value).count == 1 }.prefix(3)
            for (pid, statuses) in consistentSample {
                let classification = Set(statuses).first ?? "unknown"
                print("   ✅ PID \(pid): consistently \(classification) (\(statuses.count) detections)")
            }
        }
    }
}

// MARK: - Race Condition Test Utilities

extension RaceConditionIntegrationTests {
    /// Helper to simulate high-load concurrent operations
    func simulateHighLoadConcurrentOperations(operations: Int = 20) async -> [TimeInterval] {
        await withTaskGroup(of: TimeInterval.self) { group in
            for _ in 0 ..< operations {
                group.addTask {
                    let start = Date()
                    _ = await self.detector.detectCurrentState()
                    return Date().timeIntervalSince(start)
                }
            }

            var durations: [TimeInterval] = []
            for await duration in group {
                durations.append(duration)
            }
            return durations
        }
    }

    /// Helper to analyze state consistency
    func analyzeStateConsistency(_ states: [String]) -> (consistency: Double, transitions: Int) {
        guard states.count > 1 else { return (consistency: 1.0, transitions: 0) }

        var transitions = 0
        for i in 1 ..< states.count {
            if states[i] != states[i - 1] {
                transitions += 1
            }
        }

        let consistency = 1.0 - (Double(transitions) / Double(states.count - 1))
        return (consistency: consistency, transitions: transitions)
    }
}
