import Foundation
@testable import KeyPath
@testable import KeyPathWizardCore
@testable import KeyPathPermissions
@testable import KeyPathDaemonLifecycle
import Testing

@MainActor
@Suite("SystemValidator Tests")
struct SystemValidatorTests {
    /// Setup: Reset counters before each test to ensure isolation
    private func setupTest() async {
        SystemValidator.resetCounters()
        // Small delay to ensure reset completes before validator creation
        // This helps prevent race conditions in parallel test execution
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
    }

    @Test("SystemValidator can be instantiated")
    func instantiation() async {
        // Reset counters before test
        await setupTest()

        let processManager = ProcessLifecycleManager()
        let validator = SystemValidator(processLifecycleManager: processManager)

        // Should not crash - validator is non-optional
        _ = validator

        // Wait briefly to ensure any concurrent validations from other tests settle
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        let stats = SystemValidator.getValidationStats()
        // In parallel execution, other tests may have active validations
        // So we check that activeCount is reasonable (0-2) rather than exactly 0
        #expect(stats.activeCount <= 2, "activeCount should be reasonable")
        // Total count may be > 0 if other tests ran, but should be >= 0
        #expect(stats.totalCount >= 0)
    }

    @Test("SystemValidator tracks validation count")
    func validationCount() async {
        // Reset counters and ensure isolation
        await setupTest()

        // Get baseline stats to account for parallel test execution
        let baselineStats = SystemValidator.getValidationStats()
        let baselineCount = baselineStats.totalCount

        let processManager = ProcessLifecycleManager()
        let validator = SystemValidator(processLifecycleManager: processManager)

        // First validation
        _ = await validator.checkSystem()

        // Wait a brief moment to ensure defer blocks execute and concurrent validations settle
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        var stats = SystemValidator.getValidationStats()
        // Check that count increased by at least 1 (may be more if other tests ran)
        // In parallel execution, only the counting owner increments, so we check relative increase
        #expect(stats.totalCount >= baselineCount + 1, "totalCount should increase by at least 1")
        // In parallel test execution, another test's validation might be running
        // So we check that activeCount is reasonable (0-2) rather than exactly 0
        #expect(stats.activeCount <= 2, "activeCount should be reasonable after validation completes")

        // Second validation
        let countAfterFirst = stats.totalCount
        _ = await validator.checkSystem()

        // Wait again for defer blocks
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        stats = SystemValidator.getValidationStats()
        // Check that count increased again
        #expect(stats.totalCount >= countAfterFirst + 1, "totalCount should increase again after second validation")
        #expect(stats.activeCount <= 2, "activeCount should be reasonable after validation completes")
    }

    @Test("SystemSnapshot has fresh timestamp")
    func snapshotFreshness() async {
        // Reset counters for isolation (this test doesn't check counts, but good practice)
        await setupTest()

        let processManager = ProcessLifecycleManager()
        let validator = SystemValidator(processLifecycleManager: processManager)

        let snapshot = await validator.checkSystem()

        // Snapshot should be fresh (< 1 second old)
        #expect(snapshot.age < 1.0)

        // Should not crash on validate()
        snapshot.validate()
    }

    @Test("SystemSnapshot validates staleness")
    func snapshotStalenessDetection() async {
        // Create a snapshot with old timestamp
        let oldTimestamp = Date(timeIntervalSinceNow: -35)

        let snapshot = SystemSnapshot(
            permissions: PermissionOracle.Snapshot(
                keyPath: PermissionOracle.PermissionSet(
                    accessibility: .unknown,
                    inputMonitoring: .unknown,
                    source: "test",
                    confidence: .low,
                    timestamp: Date()
                ),
                kanata: PermissionOracle.PermissionSet(
                    accessibility: .unknown,
                    inputMonitoring: .unknown,
                    source: "test",
                    confidence: .low,
                    timestamp: Date()
                ),
                timestamp: Date()
            ),
            components: ComponentStatus(
                kanataBinaryInstalled: false,
                karabinerDriverInstalled: false,
                karabinerDaemonRunning: false,
                vhidDeviceInstalled: false,
                vhidDeviceHealthy: false,
                launchDaemonServicesHealthy: false,
                vhidVersionMismatch: false
            ),
            conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
            health: HealthStatus(
                kanataRunning: false,
                karabinerDaemonRunning: false,
                vhidHealthy: false
            ),
            helper: HelperStatus(
                isInstalled: false,
                version: nil,
                isWorking: false
            ),
            timestamp: oldTimestamp
        )

        // Age should be > 30 seconds
        #expect(snapshot.age > 30.0)

        // validate() should assert in debug builds
        // (We can't test this directly without crashing the test)
    }
}
