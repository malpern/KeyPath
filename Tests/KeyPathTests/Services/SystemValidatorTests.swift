import Foundation
@testable import KeyPath
import Testing

@MainActor
@Suite("SystemValidator Tests")
struct SystemValidatorTests {
    @Test("SystemValidator can be instantiated")
    func instantiation() async {
        // Reset counters before test
        SystemValidator.resetCounters()

        let processManager = ProcessLifecycleManager(kanataManager: nil)
        let validator = SystemValidator(processLifecycleManager: processManager)

        // Should not crash
        #expect(validator != nil)

        let stats = SystemValidator.getValidationStats()
        #expect(stats.activeCount == 0)
        #expect(stats.totalCount == 0)
    }

    @Test("SystemValidator tracks validation count")
    func validationCount() async {
        // Reset counters
        SystemValidator.resetCounters()

        let processManager = ProcessLifecycleManager(kanataManager: nil)
        let validator = SystemValidator(processLifecycleManager: processManager)

        // First validation
        _ = await validator.checkSystem()

        var stats = SystemValidator.getValidationStats()
        #expect(stats.totalCount == 1)
        #expect(stats.activeCount == 0) // Should be 0 after completion

        // Second validation
        _ = await validator.checkSystem()

        stats = SystemValidator.getValidationStats()
        #expect(stats.totalCount == 2)
        #expect(stats.activeCount == 0)
    }

    @Test("SystemSnapshot has fresh timestamp")
    func snapshotFreshness() async {
        let processManager = ProcessLifecycleManager(kanataManager: nil)
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
            timestamp: oldTimestamp
        )

        // Age should be > 30 seconds
        #expect(snapshot.age > 30.0)

        // validate() should assert in debug builds
        // (We can't test this directly without crashing the test)
    }
}
