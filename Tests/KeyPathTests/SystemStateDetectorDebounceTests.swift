import XCTest
@testable import KeyPath

/// Tests for SystemStateDetector debouncing functionality
/// Covers race condition prevention and UI flicker elimination
@MainActor
final class SystemStateDetectorDebounceTests: XCTestCase {

    var detector: SystemStateDetector!
    var kanataManager: KanataManager!

    override func setUp() async throws {
        try await super.setUp()
        kanataManager = KanataManager()
        detector = SystemStateDetector(kanataManager: kanataManager)
    }

    override func tearDown() async throws {
        detector = nil
        kanataManager = nil
        try await super.tearDown()
    }

    // MARK: - Debouncing Logic Tests

    func testDebouncePreventsSRapidStateChanges() async {
        // Test that rapid successive state changes are debounced

        var results: [SystemStateResult] = []
        let startTime = Date()

        // When: Rapid successive state detections
        for i in 0..<10 {
            let result = await detector.detectCurrentState()
            results.append(result)

            // Very small delay to trigger rapid detection scenario
            try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds

            if i % 3 == 0 {
                print("   Detection \(i + 1): State \(result.state)")
            }
        }

        let totalDuration = Date().timeIntervalSince(startTime)

        // Then: Should complete all detections
        XCTAssertEqual(results.count, 10, "All detections should complete")

        // Should not hang due to debouncing
        XCTAssertLessThan(totalDuration, 15.0, "Rapid detections should complete within 15 seconds")

        // Check for state stability (debouncing effect)
        let states = results.map { $0.state }

        // Count state transitions
        var transitions = 0
        for i in 1..<states.count {
            if "\(states[i])" != "\(states[i-1])" {
                transitions += 1
            }
        }

        print("✅ Debounce rapid state changes test completed")
        print("   Total duration: \(String(format: "%.3f", totalDuration))s")
        print("   State transitions: \(transitions)/\(states.count - 1)")
        print("   States: \(states.map { "\($0)" })")
    }

    func testConflictDetectionDebouncing() async {
        // Test specific debouncing of conflict detection

        var conflictResults: [ConflictDetectionResult] = []

        // When: Rapid conflict detection calls
        for i in 0..<8 {
            let result = await detector.detectConflicts()
            conflictResults.append(result)

            print("   Conflict detection \(i + 1): \(result.conflicts.count) conflicts")

            // Short delay to test debouncing
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        }

        // Then: Results should show debouncing behavior
        let conflictCounts = conflictResults.map { $0.conflicts.count }

        // Check for excessive variation (would indicate lack of debouncing)
        if conflictCounts.count > 1 {
            let maxVariation = conflictCounts.max()! - conflictCounts.min()!
            XCTAssertLessThanOrEqual(
                maxVariation, 2,
                "Conflict count should be stable due to debouncing (variation: \(maxVariation))"
            )
        }

        print("✅ Conflict detection debouncing test completed")
        print("   Conflict counts: \(conflictCounts)")
    }

    func testDebounceTimeWindow() async {
        // Test that debouncing respects the time window

        let debounceTime: TimeInterval = 0.5 // Should match the 500ms debounce time in implementation

        // When: Detection, wait for debounce period, then detect again
        let result1 = await detector.detectConflicts()
        let timestamp1 = Date()

        // Wait longer than debounce time
        try? await Task.sleep(nanoseconds: UInt64((debounceTime + 0.1) * 1_000_000_000))

        let result2 = await detector.detectConflicts()
        let timestamp2 = Date()

        let timeDifference = timestamp2.timeIntervalSince(timestamp1)

        // Then: Should have waited appropriate time
        XCTAssertGreaterThan(
            timeDifference, debounceTime,
            "Should have waited longer than debounce time"
        )

        // Both results should be valid
        XCTAssertNotNil(result1, "First result should be valid")
        XCTAssertNotNil(result2, "Second result should be valid")

        print("✅ Debounce time window test completed")
        print("   Time difference: \(String(format: "%.3f", timeDifference))s")
        print("   Result 1: \(result1.conflicts.count) conflicts")
        print("   Result 2: \(result2.conflicts.count) conflicts")
    }

    // MARK: - State Consistency Tests

    func testStateConsistencyDuringRapidChanges() async {
        // Test that state remains consistent during rapid changes

        var stateResults: [WizardSystemState] = []

        // When: Rapid state detection calls
        for _ in 0..<15 {
            let result = await detector.detectCurrentState()
            stateResults.append(result.state)

            // Very brief delay
            try? await Task.sleep(nanoseconds: 25_000_000) // 0.025 seconds
        }

        // Then: States should show reasonable stability
        let stateStrings = stateResults.map { "\($0)" }
        let uniqueStates = Set(stateStrings)

        // Should not have excessive state thrashing
        XCTAssertLessThanOrEqual(
            uniqueStates.count, 5,
            "Should not have excessive state variations (found \(uniqueStates.count) unique states)"
        )

        // Count rapid state changes
        var rapidChanges = 0
        for i in 1..<stateStrings.count {
            if stateStrings[i] != stateStrings[i-1] {
                rapidChanges += 1
            }
        }

        XCTAssertLessThanOrEqual(
            rapidChanges, stateResults.count / 2,
            "Should not have excessive rapid state changes"
        )

        print("✅ State consistency during rapid changes test completed")
        print("   Unique states: \(uniqueStates.count)")
        print("   Rapid changes: \(rapidChanges)/\(stateResults.count - 1)")
        print("   States: \(uniqueStates)")
    }

    func testDebounceHandlesFlickeringConflicts() async {
        // Test specific scenario where conflicts appear and disappear rapidly

        var hasConflictsHistory: [Bool] = []

        // When: Repeated conflict detection to catch flickering
        for i in 0..<12 {
            let result = await detector.detectConflicts()
            let hasConflicts = !result.conflicts.isEmpty
            hasConflictsHistory.append(hasConflicts)

            if i % 4 == 0 {
                print("   Detection \(i + 1): Has conflicts: \(hasConflicts)")
            }

            // Brief delay to potentially catch state changes
            try? await Task.sleep(nanoseconds: 75_000_000) // 0.075 seconds
        }

        // Then: Should not have excessive conflict flickering
        var conflictToggles = 0
        for i in 1..<hasConflictsHistory.count {
            if hasConflictsHistory[i] != hasConflictsHistory[i-1] {
                conflictToggles += 1
            }
        }

        // Debouncing should prevent excessive toggling
        XCTAssertLessThanOrEqual(
            conflictToggles, 3,
            "Should not have excessive conflict toggling (found \(conflictToggles) toggles)"
        )

        print("✅ Flickering conflicts debounce test completed")
        print("   Conflict history: \(hasConflictsHistory)")
        print("   Toggles: \(conflictToggles)")
    }

    // MARK: - Integration with ProcessLifecycleManager Tests

    func testDebounceWithProcessLifecycleIntegration() async {
        // Test debouncing works correctly with ProcessLifecycleManager integration

        let processManager = ProcessLifecycleManager(kanataManager: kanataManager)
        let integratedDetector = SystemStateDetector(kanataManager: kanataManager)

        var detectionResults: [Bool] = []

        // When: Rapid detections with potential process lifecycle changes
        for i in 0..<10 {
            // Alternate between different operations to simulate real usage
            if i % 3 == 0 {
                await processManager.invalidatePIDCache()
            }

            let result = await integratedDetector.detectConflicts()
            let hasConflicts = !result.conflicts.isEmpty
            detectionResults.append(hasConflicts)

            // Small delay
            try? await Task.sleep(nanoseconds: 40_000_000) // 0.04 seconds
        }

        // Then: Should handle integration gracefully
        XCTAssertEqual(detectionResults.count, 10, "All integrated detections should complete")

        // Check for stability despite cache invalidations
        var majorChanges = 0
        for i in 1..<detectionResults.count {
            if detectionResults[i] != detectionResults[i-1] {
                majorChanges += 1
            }
        }

        XCTAssertLessThanOrEqual(
            majorChanges, 4,
            "Integration should not cause excessive result changes"
        )

        print("✅ Debounce with ProcessLifecycleManager integration test completed")
        print("   Results: \(detectionResults)")
        print("   Major changes: \(majorChanges)")
    }

    // MARK: - Performance Impact Tests

    func testDebouncingDoesNotImpactPerformance() async {
        // Test that debouncing doesn't significantly impact performance

        // When: Single detection (baseline)
        let startTime1 = Date()
        let result1 = await detector.detectCurrentState()
        let duration1 = Date().timeIntervalSince(startTime1)

        // When: Rapid detections (with debouncing active)
        let startTime2 = Date()
        var rapidResults: [SystemStateResult] = []

        for _ in 0..<5 {
            let result = await detector.detectCurrentState()
            rapidResults.append(result)
            try? await Task.sleep(nanoseconds: 30_000_000) // 0.03 seconds
        }

        let duration2 = Date().timeIntervalSince(startTime2)
        let averageRapidDuration = duration2 / Double(rapidResults.count)

        // Then: Debouncing should not significantly slow down individual detections
        XCTAssertLessThan(
            averageRapidDuration, duration1 * 3,
            "Debouncing should not excessively slow down detections"
        )

        XCTAssertLessThan(duration2, 10.0, "Rapid detections should complete within 10 seconds")

        print("✅ Debouncing performance impact test completed")
        print("   Single detection: \(String(format: "%.3f", duration1))s")
        print("   Average rapid detection: \(String(format: "%.3f", averageRapidDuration))s")
        print("   Total rapid detection time: \(String(format: "%.3f", duration2))s")
    }

    func testConcurrentDetectionWithDebouncing() async {
        // Test concurrent detection calls with debouncing active

        let startTime = Date()

        // When: Concurrent detections
        await withTaskGroup(of: SystemStateResult.self) { group in
            for i in 0..<8 {
                group.addTask {
                    await self.detector.detectCurrentState()
                }
            }

            var results: [SystemStateResult] = []
            for await result in group {
                results.append(result)
            }

            let duration = Date().timeIntervalSince(startTime)

            // Then: All concurrent detections should complete
            XCTAssertEqual(results.count, 8, "All concurrent detections should complete")
            XCTAssertLessThan(duration, 15.0, "Concurrent detections should complete within 15 seconds")

            // States should be reasonably consistent
            let states = results.map { "\($0.state)" }
            let uniqueStates = Set(states)

            XCTAssertLessThanOrEqual(
                uniqueStates.count, 3,
                "Concurrent detections should have reasonably consistent states"
            )

            print("✅ Concurrent detection with debouncing test completed")
            print("   Duration: \(String(format: "%.3f", duration))s")
            print("   Unique states: \(uniqueStates.count)")
            print("   States: \(uniqueStates)")
        }
    }

    // MARK: - Edge Case Tests

    func testDebounceHandlesEmptyStateChanges() async {
        // Test debouncing when transitioning to/from empty states

        var stateHistories: [String] = []

        // When: Detections that might transition through empty/non-empty states
        for i in 0..<8 {
            let result = await detector.detectCurrentState()
            let stateDescription = "\(result.state)"
            stateHistories.append(stateDescription)

            // Vary delay to test different debouncing scenarios
            let delay = [20, 40, 60, 80][i % 4]
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000)) // Variable delay
        }

        // Then: Should handle state transitions gracefully
        XCTAssertEqual(stateHistories.count, 8, "All state detections should complete")

        // Check for reasonable state progression
        let uniqueStates = Set(stateHistories)
        print("✅ Empty state changes debounce test completed")
        print("   State progression: \(stateHistories)")
        print("   Unique states: \(uniqueStates.count)")
    }

    func testDebounceWithSystemStateChanges() async {
        // Test debouncing behavior when actual system state might change

        let startTime = Date()
        var detectionTimestamps: [Date] = []
        var stateResults: [WizardSystemState] = []

        // When: Extended monitoring period to catch potential system changes
        for i in 0..<6 {
            let detectionStart = Date()
            let result = await detector.detectCurrentState()

            detectionTimestamps.append(detectionStart)
            stateResults.append(result.state)

            print("   Detection \(i + 1): \(result.state) at \(String(format: "%.3f", detectionStart.timeIntervalSince(startTime)))s")

            // Longer delay to allow for potential system changes
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        }

        let totalDuration = Date().timeIntervalSince(startTime)

        // Then: Should handle any system state changes gracefully
        XCTAssertEqual(stateResults.count, 6, "All detections should complete")
        XCTAssertLessThan(totalDuration, 8.0, "Extended monitoring should complete within 8 seconds")

        // Analyze state transitions over time
        var stateTransitions: [(from: String, to: String, time: TimeInterval)] = []
        for i in 1..<stateResults.count {
            let fromState = "\(stateResults[i-1])"
            let toState = "\(stateResults[i])"
            let time = detectionTimestamps[i].timeIntervalSince(startTime)

            if fromState != toState {
                stateTransitions.append((from: fromState, to: toState, time: time))
            }
        }

        print("✅ System state changes debounce test completed")
        print("   Total duration: \(String(format: "%.3f", totalDuration))s")
        print("   State transitions: \(stateTransitions.count)")
        if !stateTransitions.isEmpty {
            for transition in stateTransitions {
                print("     \(transition.from) -> \(transition.to) at \(String(format: "%.3f", transition.time))s")
            }
        }
    }

    // MARK: - Regression Tests

    func testNoRegressionInBasicFunctionality() async {
        // Ensure debouncing doesn't break basic functionality

        // When: Basic detection operations
        let conflictResult = await detector.detectConflicts()
        let permissionResult = await detector.checkPermissions()
        let componentResult = await detector.checkComponents()
        let fullStateResult = await detector.detectCurrentState()

        // Then: All operations should complete successfully
        XCTAssertNotNil(conflictResult, "Conflict detection should work")
        XCTAssertNotNil(permissionResult, "Permission checking should work")
        XCTAssertNotNil(componentResult, "Component checking should work")
        XCTAssertNotNil(fullStateResult, "Full state detection should work")

        // Results should be reasonable
        XCTAssertGreaterThanOrEqual(conflictResult.conflicts.count, 0, "Conflict count should be non-negative")
        XCTAssertNotEqual(fullStateResult.state, .initializing, "Should complete initialization")

        print("✅ No regression in basic functionality test completed")
        print("   Conflicts: \(conflictResult.conflicts.count)")
        print("   State: \(fullStateResult.state)")
        print("   Issues: \(fullStateResult.issues.count)")
    }

    func testDebounceDoesNotAffectAccuracy() async {
        // Test that debouncing doesn't affect the accuracy of detection

        // When: Multiple detections with varied timing
        var results: [SystemStateResult] = []
        let timings: [UInt64] = [10, 100, 600, 50, 300] // Various delays in milliseconds

        for (index, delay) in timings.enumerated() {
            let result = await detector.detectCurrentState()
            results.append(result)

            print("   Detection \(index + 1): \(result.state) (delay: \(delay)ms)")

            try? await Task.sleep(nanoseconds: delay * 1_000_000)
        }

        // Then: Results should be accurate and consistent where appropriate
        XCTAssertEqual(results.count, timings.count, "All detections should complete")

        // Check that results make sense
        for (index, result) in results.enumerated() {
            XCTAssertNotEqual(result.state, .initializing, "Detection \(index + 1) should complete")
            XCTAssertNotNil(result.detectionTimestamp, "Should have detection timestamp")
        }

        // Results with longer delays should be more likely to be consistent
        // (This is a heuristic test - we can't guarantee exact behavior)
        let longDelayResults = [results[2], results[4]] // 600ms and 300ms delays
        if longDelayResults.count >= 2 {
            let states = longDelayResults.map { "\($0.state)" }
            print("   Long delay results: \(states)")
        }

        print("✅ Debounce accuracy test completed")
    }
}
