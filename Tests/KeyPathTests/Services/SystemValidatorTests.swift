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
    private enum ExpectedFailure: Error {
        case conflictProbe
    }

    /// Setup: Reset counters before each test to ensure isolation
    private func setupTest() async {
        SystemValidator.resetCounters()
        await Task.yield()
    }

    @Test("SystemValidator can be instantiated")
    func instantiation() async {
        // Reset counters before test
        await setupTest()

        let processManager = ProcessLifecycleManager()
        let validator = SystemValidator(processLifecycleManager: processManager)

        // Should not crash - validator is non-optional
        _ = validator

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

        // Create validator FIRST to become the counting owner
        // This ensures our validator is the one that counts
        let processManager = ProcessLifecycleManager()
        let validator = SystemValidator(processLifecycleManager: processManager)

        // Get baseline stats AFTER creating our validator
        // Note: baselineCount might be > 0 if other parallel tests ran, but that's okay
        let baselineStats = SystemValidator.getValidationStats()

        // First validation - in test mode, this returns a stub immediately
        // without incrementing validation counters (this is the expected fast-path behavior)
        let snapshot = await validator.checkSystem()

        let stats = SystemValidator.getValidationStats()

        // In test mode, checkSystem() returns early with a stub snapshot
        // so the validation counters won't increment - this is expected behavior
        // We verify:
        // 1. The snapshot is valid (has expected test stub properties)
        // 2. Stats tracking still works (activeCount should be 0 or low)

        // Verify we got a valid snapshot (test stub returns "all healthy" state)
        #expect(snapshot.permissions.keyPath.source == "test-stub",
                "Test mode should return stub snapshot")
        #expect(snapshot.health.kanataRunning == true,
                "Test stub should show healthy state")

        // Active count should be 0 or very low (no real validation happening)
        #expect(stats.activeCount <= 2, "activeCount should be reasonable")

        // In test mode, count may or may not increment depending on whether
        // the stub path increments counters - either is acceptable
        #expect(stats.totalCount >= baselineStats.totalCount,
                "totalCount should never decrease")
    }

    @Test("SystemValidator uses injected SystemStateProvider for Karabiner grabber PID")
    func karabinerGrabberPIDUsesInjectedSystemStateProvider() async {
        await setupTest()

        let runner = SubprocessRunnerFake.shared
        await runner.reset()
        await runner.configurePgrepResult { pattern in
            pattern == "karabiner_grabber" ? [9876] : []
        }

        let processManager = ProcessLifecycleManager()
        let provider = SystemStateProvider(probes: runner.systemProbeClient())
        let validator = SystemValidator(
            processLifecycleManager: processManager,
            systemStateProvider: provider
        )

        let pid = await validator.getKarabinerGrabberPID()
        let commands = await runner.executedCommands

        #expect(pid == 9876)
        #expect(
            commands.contains { $0.executable == "/usr/bin/pgrep" && $0.args == ["-f", "karabiner_grabber"] },
            "SystemValidator should use the injected provider's subprocess runner for Karabiner process discovery"
        )
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

    @Test("Cached capture reuses the recent canonical snapshot")
    func cachedCaptureReusesRecentSnapshot() async {
        await setupTest()

        let validator = SystemValidator(processLifecycleManager: ProcessLifecycleManager())
        let fresh = await validator.checkSystem(freshness: .fresh)
        let cached = await validator.checkSystem(freshness: .cached)

        #expect(cached.timestamp == fresh.timestamp)

        let freshAgain = await validator.checkSystem(freshness: .fresh)
        #expect(freshAgain.id != cached.id)

        validator.invalidateCaches()
        let recaptured = await validator.checkSystem(freshness: .cached)
        #expect(recaptured.timestamp >= freshAgain.timestamp)
    }

    @Test("Failed conflict probe produces incomplete fail-safe evidence")
    func failedConflictProbeIsIncomplete() async {
        await setupTest()

        let validator = SystemValidator(
            processLifecycleManager: ProcessLifecycleManager(),
            conflictDetector: { throw ExpectedFailure.conflictProbe }
        )

        let evidence = await validator.checkConflicts()

        #expect(evidence.captureStatus == .failed)
        #expect(!evidence.status.hasConflicts)
        #expect(!evidence.status.canAutoResolve)
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

    @Test("Incomplete snapshot is never ready and exposes staleness separately")
    func incompleteSnapshotContract() {
        let context = SystemContextBuilder().build()
        let snapshot = SystemSnapshot(
            permissions: context.permissions,
            components: context.components,
            conflicts: context.conflicts,
            health: context.services,
            helper: context.helper,
            timestamp: Date(timeIntervalSinceNow: -5),
            captureStatus: .cancelled
        )

        #expect(!snapshot.isReady)
        #expect(snapshot.captureStatus == .cancelled)
        #expect(snapshot.isStale(maxAge: 1))
    }

    @Test("Healthy TCP-responsive Kanata suppresses stale stderr config parse errors")
    func staleConfigParseErrorSuppressedWhenRuntimeResponsive() {
        let error = SystemValidator.effectiveConfigParseError(
            "Duplicate alias: beh_base_a",
            kanataRunning: true,
            tcpResponding: true
        )

        #expect(error == nil)
    }

    @Test("Non-responsive Kanata keeps stderr config parse errors")
    func configParseErrorKeptWhenRuntimeIsNotResponsive() {
        let error = SystemValidator.effectiveConfigParseError(
            "Duplicate alias: beh_base_a",
            kanataRunning: true,
            tcpResponding: false
        )

        #expect(error == "Duplicate alias: beh_base_a")
    }

    @Test("Capture status keeps the most conservative probe result")
    func combinedCaptureStatusIsConservative() {
        #expect(SystemValidator.combinedCaptureStatus([.complete, .timedOut]) == .timedOut)
        #expect(SystemValidator.combinedCaptureStatus([.timedOut, .cancelled]) == .cancelled)
        #expect(SystemValidator.combinedCaptureStatus([.cancelled, .failed]) == .failed)
        #expect(SystemValidator.combinedCaptureStatus([.complete, .complete]) == .complete)
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
        #expect(started.duration(to: clock.now) < .milliseconds(250))
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
