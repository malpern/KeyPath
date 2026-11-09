import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathDaemonLifecycle
@testable import KeyPathPermissions
@testable import KeyPathWizardCore
import Testing

@MainActor
@Suite("SystemValidator Tests")
struct SystemValidatorTests {
    @Test("SystemSnapshot has fresh timestamp")
    func snapshotFreshness() async {
        let validator = SystemValidator()

        let snapshot = await validator.checkSystem()

        // Snapshot should be fresh (< 1 second old)
        #expect(snapshot.age < 1.0)

        // Should not crash on validate()
        snapshot.validate()
    }

    @Test("Cached capture reuses the recent canonical snapshot")
    func cachedCaptureReusesRecentSnapshot() async {
        let validator = SystemValidator()
        let fresh = await validator.checkSystem(freshness: .fresh)
        let cached = await validator.checkSystem(freshness: .cached)

        #expect(cached.timestamp == fresh.timestamp)

        let freshAgain = await validator.checkSystem(freshness: .fresh)
        #expect(freshAgain.id != cached.id)

        validator.invalidateCaches()
        let recaptured = await validator.checkSystem(freshness: .cached)
        #expect(recaptured.timestamp >= freshAgain.timestamp)
    }

    @Test("SystemSnapshot validates staleness")
    func snapshotStalenessDetection() {
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
                vhidServicesHealthy: false,
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

    @Test("Incomplete snapshot is never ready and exposes staleness separately")
    func incompleteSnapshotContract() {
        let context = SystemContextBuilder().build()
        let snapshot = SystemSnapshot(
            permissions: context.permissions,
            components: context.components,
            conflicts: context.conflicts,
            health: context.services,
            timestamp: Date(timeIntervalSinceNow: -5),
            captureStatus: .cancelled
        )

        #expect(!snapshot.isReady)
        #expect(snapshot.captureStatus == .cancelled)
        #expect(snapshot.isStale(maxAge: 1))
    }

    @Test("Captured missing TCP configuration makes health incomplete")
    func missingTCPConfigurationIsUnhealthy() {
        let health = HealthStatus(
            kanataTCPConfigured: false,
            kanataRunning: true,
            karabinerDaemonRunning: true,
            vhidHealthy: true
        )

        #expect(!health.isHealthy)
    }

    @Test("Canonical capture timeout returns first-class timed-out evidence")
    func canonicalCaptureTimeout() async {
        let clock = ContinuousClock()
        let started = clock.now
        let snapshot = await SystemValidator.boundedCapture(timeout: 0.01) {
            while !Task.isCancelled {
                await Task.yield()
            }
            return .unavailable(captureStatus: .failed, source: "late-test-result")
        }

        #expect(snapshot.captureStatus == .timedOut)
        // Generous bound: only guards against boundedCapture hanging past its
        // 10ms deadline, not scheduling latency on a loaded runner.
        #expect(started.duration(to: clock.now) < .seconds(5))
    }

    @Test("Canonical capture returns completed evidence before its deadline")
    func canonicalCaptureCompletes() async {
        let expected = SystemSnapshot.unavailable(captureStatus: .failed, source: "test-result")
        let snapshot = await SystemValidator.boundedCapture(timeout: 1) { expected }

        #expect(snapshot.id == expected.id)
        #expect(snapshot.captureStatus == .failed)
    }

    @Test("Cancelling canonical capture returns cancelled evidence")
    func canonicalCaptureCancellation() async {
        let capture = Task { @MainActor in
            await SystemValidator.boundedCapture(timeout: 1) {
                while !Task.isCancelled {
                    await Task.yield()
                }
                return .unavailable(captureStatus: .failed, source: "late-test-result")
            }
        }
        await Task.yield()
        capture.cancel()

        let snapshot = await capture.value
        #expect(snapshot.captureStatus == .cancelled)
    }
}
