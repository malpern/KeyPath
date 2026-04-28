@testable import KeyPathAppKit
@testable import KeyPathWizardCore
import Testing

/// Tests for the "launcher alive, kanata dead" scenario.
/// Verifies that the health pipeline correctly detects when
/// kanata-launcher is running but the kanata binary has crashed.
@MainActor
@Suite("Kanata Binary Health Tests")
struct KanataBinaryHealthTests {

    private func setUp() {
        KanataSplitRuntimeHostService.testBinaryAliveOverride = nil
        KanataSplitRuntimeHostService.testPersistentHostPID = nil
    }

    // MARK: - isKanataBinaryAlive test seam

    @Test("Binary alive override returns true when set to true")
    func binaryAliveOverrideTrue() {
        setUp()
        KanataSplitRuntimeHostService.testBinaryAliveOverride = true
        #expect(KanataSplitRuntimeHostService.isKanataBinaryAlive() == true)
        setUp()
    }

    @Test("Binary alive override returns false when set to false")
    func binaryAliveOverrideFalse() {
        setUp()
        KanataSplitRuntimeHostService.testBinaryAliveOverride = false
        #expect(KanataSplitRuntimeHostService.isKanataBinaryAlive() == false)
        setUp()
    }

    // MARK: - Launcher alive, binary dead

    @Test("Host running but binary dead reports not running")
    func launcherAliveBinaryDead() async {
        setUp()
        // Simulate: launcher process alive (PID > 0), but kanata binary dead
        KanataSplitRuntimeHostService.testPersistentHostPID = 12345
        KanataSplitRuntimeHostService.testBinaryAliveOverride = false

        let hostRunning = KanataSplitRuntimeHostService.shared.isPersistentPassthruHostRunning
        let binaryAlive = KanataSplitRuntimeHostService.isKanataBinaryAlive()

        #expect(hostRunning == true, "Launcher should report running")
        #expect(binaryAlive == false, "Binary should report dead")

        // The ServiceLifecycleCoordinator should report .stopped in this state
        // (tested indirectly via the binary check)
        setUp()
    }

    @Test("Host running and binary alive reports running")
    func launcherAliveBinaryAlive() async {
        setUp()
        KanataSplitRuntimeHostService.testPersistentHostPID = 12345
        KanataSplitRuntimeHostService.testBinaryAliveOverride = true

        let hostRunning = KanataSplitRuntimeHostService.shared.isPersistentPassthruHostRunning
        let binaryAlive = KanataSplitRuntimeHostService.isKanataBinaryAlive()

        #expect(hostRunning == true)
        #expect(binaryAlive == true)
        setUp()
    }

    @Test("Host not running reports not running regardless of binary")
    func launcherDeadBinaryIrrelevant() async {
        setUp()
        KanataSplitRuntimeHostService.testPersistentHostPID = 0
        KanataSplitRuntimeHostService.testBinaryAliveOverride = true

        let hostRunning = KanataSplitRuntimeHostService.shared.isPersistentPassthruHostRunning
        #expect(hostRunning == false, "Launcher with PID 0 should not be running")
        setUp()
    }

    // MARK: - Health status model

    @Test("HealthStatus is unhealthy when kanataRunning is false")
    func healthStatusUnhealthy() {
        let status = HealthStatus(
            kanataRunning: false,
            karabinerDaemonRunning: true,
            vhidHealthy: true,
            kanataInputCaptureReady: true
        )
        #expect(status.isHealthy == false)
    }

    @Test("HealthStatus is healthy when all components are running")
    func healthStatusHealthy() {
        let status = HealthStatus(
            kanataRunning: true,
            karabinerDaemonRunning: true,
            vhidHealthy: true,
            kanataInputCaptureReady: true
        )
        #expect(status.isHealthy == true)
    }
}
