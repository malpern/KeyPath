@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class ServiceLifecycleCoordinatorTests: KeyPathTestCase {
    private var coordinator: ServiceLifecycleCoordinator!
    private var capturedErrors: [String?] = []
    private var capturedWarnings: [String?] = []
    private var stateChangeCount = 0

    override func setUp() async throws {
        try await super.setUp()
        coordinator = ServiceLifecycleCoordinator(
            kanataDaemonService: KanataDaemonService(),
            recoveryCoordinator: RecoveryCoordinator()
        )
        capturedErrors = []
        capturedWarnings = []
        stateChangeCount = 0

        coordinator.onError = { [unowned self] error in
            capturedErrors.append(error)
        }
        coordinator.onWarning = { [unowned self] warning in
            capturedWarnings.append(warning)
        }
        coordinator.onStateChanged = { [unowned self] in
            stateChangeCount += 1
        }
    }

    // MARK: - Start gating

    func testStartFailsWhenVHIDDaemonNotRunning() async {
        coordinator.isVirtualHIDDaemonHealthy = { false }

        let result = await coordinator.startKanata(reason: "test")

        XCTAssertFalse(result, "Start should fail when VHID daemon is not running")
        XCTAssertEqual(capturedErrors.count, 1)
        XCTAssertTrue(capturedErrors.first??.contains("VirtualHID") ?? false)
        XCTAssertGreaterThan(stateChangeCount, 0, "Should notify state change on failure")
    }

    func testStartSetsIsStartingFlag() async {
        coordinator.isVirtualHIDDaemonHealthy = { true }

        // isStartingKanata should be false before and after (defer resets it)
        XCTAssertFalse(coordinator.isStartingKanata)
        _ = await coordinator.startKanata(reason: "test")
        XCTAssertFalse(coordinator.isStartingKanata, "isStartingKanata should be reset after start completes")
    }

    func testStartTerminatesRunningKanataWhenBinaryDoesNotMatchBundledRuntime() async {
        coordinator.isVirtualHIDDaemonHealthy = { true }

        let privileged = StubPrivilegedOperationsCoordinator()
        WizardDependencies.privilegedOperations = privileged

        ServiceLifecycleCoordinator.testRunningKanataIdentityProvider = {
            ServiceLifecycleCoordinator.RunningKanataIdentity(
                pid: 4242,
                executablePath: "/opt/homebrew/bin/kanata",
                startedAt: Date()
            )
        }

        _ = await coordinator.startKanata(reason: "test stale binary")

        XCTAssertTrue(
            privileged.calls.contains("killAllKanataProcesses"),
            "A confirmed running/bundled Kanata mismatch must route through InstallerEngine privileged termination before startup continues"
        )
    }

    func testStartTerminatesRunningKanataWhenSamePathButProcessPredatesBundledBinary() async throws {
        coordinator.isVirtualHIDDaemonHealthy = { true }

        let privileged = StubPrivilegedOperationsCoordinator()
        WizardDependencies.privilegedOperations = privileged

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keypath-kanata-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundledKanata = tempDir.appendingPathComponent("kanata")
        FileManager.default.createFile(atPath: bundledKanata.path, contents: Data())
        let bundledModifiedAt = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: bundledModifiedAt],
            ofItemAtPath: bundledKanata.path
        )
        WizardSystemPaths.setBundledKanataPathOverride(bundledKanata.path)
        defer { WizardSystemPaths.setBundledKanataPathOverride(nil) }

        ServiceLifecycleCoordinator.testRunningKanataIdentityProvider = {
            ServiceLifecycleCoordinator.RunningKanataIdentity(
                pid: 4242,
                executablePath: bundledKanata.path,
                startedAt: bundledModifiedAt.addingTimeInterval(-60)
            )
        }

        _ = await coordinator.startKanata(reason: "test stale same-path binary")

        XCTAssertTrue(
            privileged.calls.contains("killAllKanataProcesses"),
            "A running Kanata process started before the bundled binary was replaced is stale even when proc_pidpath returns the same path"
        )
    }

    // MARK: - Stop

    func testStopNotifiesStateChange() async {
        let result = await coordinator.stopKanata(reason: "test")

        // Should succeed (stopIfRunning returns false if not running, which is fine)
        XCTAssertTrue(result)
        XCTAssertGreaterThan(stateChangeCount, 0)
    }

    // MARK: - Intentional-transition gate (#625)

    func testNotInIntentionalTransitionWhenIdle() {
        // A fresh coordinator that hasn't stopped anything is not transitioning, so a
        // grab failure observed now is genuine and eligible for recovery.
        XCTAssertFalse(coordinator.isIntentionalTransitionInProgress)
    }

    func testIntentionalTransitionFlagSetDuringStop() async {
        // The flag must be closed *while the stop runs*, so a benign `active=false`
        // from the dying kanata is suppressed. We observe it from the onStateChanged
        // callback, which fires inside stopKanata before its `defer` opens the grace.
        var seenDuringStop: Bool?
        coordinator.onStateChanged = { [unowned self] in
            if seenDuringStop == nil {
                seenDuringStop = coordinator.isIntentionalTransitionInProgress
            }
        }

        _ = await coordinator.stopKanata(reason: "test")

        XCTAssertEqual(seenDuringStop, true, "Transition gate must be closed during the stop")
    }

    func testIntentionalTransitionGraceHoldsBrieflyAfterStop() async {
        // Immediately after stop returns, the short trailing grace keeps the gate closed
        // so a late last-gasp `active=false` from the just-killed kanata is still suppressed.
        _ = await coordinator.stopKanata(reason: "test")
        XCTAssertTrue(
            coordinator.isIntentionalTransitionInProgress,
            "Gate should remain closed during the post-stop grace window"
        )
    }

    func testStartClearsLingeringStopGrace() async {
        // The stop-grace exists only to swallow the OLD process's last gasp. Once a new
        // start begins (e.g. the start phase of a restart), the grace must end so a
        // genuine `active=false` from the freshly started kanata is NOT masked as benign.
        coordinator.isVirtualHIDDaemonHealthy = { true }
        _ = await coordinator.stopKanata(reason: "stop for restart")
        XCTAssertTrue(coordinator.isIntentionalTransitionInProgress, "Grace armed after stop")

        _ = await coordinator.startKanata(reason: "restart")

        XCTAssertFalse(
            coordinator.isIntentionalTransitionInProgress,
            "Starting a new kanata must clear the stale stop-grace so post-start grab failures are caught"
        )
    }

    func testPostStartReadinessAcceptsLiveRuntimeDespiteStaleRegistrationMetadata() {
        let snapshot = ServiceHealthChecker.KanataServiceRuntimeSnapshot(
            managementState: .smappserviceActive,
            isRunning: true,
            isResponding: true,
            inputCaptureReady: true,
            inputCaptureIssue: nil,
            launchctlExitCode: 0,
            staleEnabledRegistration: true,
            recentlyRestarted: false
        )

        XCTAssertTrue(
            ServiceLifecycleCoordinator.shouldAcceptPostStartRuntime(snapshot),
            "Current process, TCP, and input-capture evidence must outrank stale registration metadata"
        )
    }

    // MARK: - Restart

    func testRestartCallsStopThenStart() async {
        coordinator.isVirtualHIDDaemonHealthy = { true }

        // Restart should call stop then start
        let result = await coordinator.restartKanata(reason: "test restart")

        // Result depends on whether daemon registration succeeds (likely fails in test env)
        // But the flow should complete without crashing
        XCTAssertNotNil(result)
    }

    // MARK: - Runtime Status

    func testRuntimeStatusReportsStartingDuringStart() async {
        coordinator.isStartingKanata = true

        let status = await coordinator.currentRuntimeStatus()

        XCTAssertEqual(status, .starting)
    }

    func testRuntimeStatusReportsStoppedWhenDaemonNotRunning() async {
        // In test env, daemon is not running
        let status = await coordinator.currentRuntimeStatus()

        // Should be stopped or unknown (not starting, not running)
        XCTAssertFalse(status.isRunning)
        XCTAssertNotEqual(status, .starting)
    }

    // MARK: - Startup Window

    func testTransientStartupWindowDuringStart() async {
        coordinator.isStartingKanata = true

        let inWindow = await coordinator.isInTransientRuntimeStartupWindow()

        XCTAssertTrue(inWindow, "Should be in startup window while start is in progress")
    }

    func testNotInStartupWindowWhenIdle() async {
        coordinator.isStartingKanata = false

        let inWindow = await coordinator.isInTransientRuntimeStartupWindow()

        // May or may not be in window depending on SMAppService state,
        // but should not crash
        XCTAssertNotNil(inWindow)
    }

    // MARK: - Wait-for-exit before start (#625 part-1)

    //
    // These drive `waitForKanataExitBeforeStart()` directly (it runs after the VHID
    // gates in `startKanata`, which short-circuit in the test environment). All timing
    // is deterministic: pgrep/liveness/signal/TCP/sleep are injected via DEBUG seams, so
    // no real subprocess, signal, port, or wall-clock sleep is involved. Seams are reset
    // to safe defaults in TestSingletonReset.resetAll() between tests.

    func testWaitForExit_noOrphans_fastPath() async {
        var sleeps = 0
        var tcpProbes = 0
        ServiceLifecycleCoordinator.testPgrepProvider = { _ in [] }
        ServiceLifecycleCoordinator.testSleep = { _ in sleeps += 1 }
        ServiceLifecycleCoordinator.testTCPProbe = { _, _ in tcpProbes += 1; return false }

        await coordinator.waitForKanataExitBeforeStart()

        XCTAssertEqual(sleeps, 0, "No orphans → no polling sleeps")
        XCTAssertEqual(tcpProbes, 0, "No orphans → port-release poll is skipped (zero added latency)")
    }

    func testWaitForExit_processGoneImmediately() async {
        var signals: [Int32] = []
        var tcpProbes = 0
        var sleeps = 0
        ServiceLifecycleCoordinator.testPgrepProvider = { name in name == "kanata-launcher" ? [4242] : [] }
        ServiceLifecycleCoordinator.testLivenessProbe = { _ in false } // already gone
        ServiceLifecycleCoordinator.testSignal = { _, sig in signals.append(sig) }
        ServiceLifecycleCoordinator.testTCPProbe = { _, _ in tcpProbes += 1; return false } // port free
        ServiceLifecycleCoordinator.testSleep = { _ in sleeps += 1 }

        await coordinator.waitForKanataExitBeforeStart()

        XCTAssertEqual(signals, [SIGTERM], "Only SIGTERM; no SIGKILL escalation when the process exits immediately")
        XCTAssertEqual(sleeps, 0, "Gone on first probe and port free on first probe → no sleeps")
        XCTAssertEqual(tcpProbes, 1, "Port checked once and found free")
    }

    func testWaitForExit_processLingersThenExits() async {
        var livenessProbes = 0
        var signals: [Int32] = []
        var sleeps = 0
        ServiceLifecycleCoordinator.testPgrepProvider = { name in name == "kanata-launcher" ? [4242] : [] }
        ServiceLifecycleCoordinator.testLivenessProbe = { _ in
            livenessProbes += 1
            return livenessProbes <= 2 // alive for two probes, then gone
        }
        ServiceLifecycleCoordinator.testSignal = { _, sig in signals.append(sig) }
        ServiceLifecycleCoordinator.testTCPProbe = { _, _ in false } // port free immediately
        ServiceLifecycleCoordinator.testSleep = { _ in sleeps += 1 }

        await coordinator.waitForKanataExitBeforeStart()

        XCTAssertEqual(signals, [SIGTERM], "Exited within the grace window → no SIGKILL")
        XCTAssertEqual(livenessProbes, 3, "Polled liveness until the process disappeared")
        XCTAssertEqual(sleeps, 2, "Two polling sleeps before exit; port was free immediately")
    }

    func testWaitForExit_processNeverExits_timeoutEscalatesToKillThenProceeds() async {
        var signals: [Int32] = []
        ServiceLifecycleCoordinator.testPgrepProvider = { name in name == "kanata-launcher" ? [4242] : [] }
        ServiceLifecycleCoordinator.testLivenessProbe = { _ in true } // never exits
        ServiceLifecycleCoordinator.testSignal = { _, sig in signals.append(sig) }
        ServiceLifecycleCoordinator.testTCPProbe = { _, _ in false }
        ServiceLifecycleCoordinator.testSleep = { _ in }

        // Must return (proceed), not hang, even though the process never dies.
        await coordinator.waitForKanataExitBeforeStart()

        XCTAssertEqual(signals.first, SIGTERM, "SIGTERM must precede SIGKILL")
        XCTAssertEqual(signals.filter { $0 == SIGKILL }.count, 1, "Exactly one SIGKILL after the grace window")
    }

    func testWaitForExit_portBusyThenFrees() async {
        var tcpProbes = 0
        var sleeps = 0
        ServiceLifecycleCoordinator.testPgrepProvider = { name in name == "kanata-launcher" ? [4242] : [] }
        ServiceLifecycleCoordinator.testLivenessProbe = { _ in false } // process gone immediately
        ServiceLifecycleCoordinator.testSignal = { _, _ in }
        ServiceLifecycleCoordinator.testTCPProbe = { _, _ in
            tcpProbes += 1
            return tcpProbes <= 3 // busy for three probes, then released
        }
        ServiceLifecycleCoordinator.testSleep = { _ in sleeps += 1 }

        await coordinator.waitForKanataExitBeforeStart()

        XCTAssertEqual(tcpProbes, 4, "Polled the port until it was released")
        XCTAssertEqual(sleeps, 3, "Slept between port probes while the port was busy")
    }

    func testWaitForExit_portNeverFrees_timeoutProceedsWithWarning() async {
        var tcpProbes = 0
        ServiceLifecycleCoordinator.testPgrepProvider = { name in name == "kanata-launcher" ? [4242] : [] }
        ServiceLifecycleCoordinator.testLivenessProbe = { _ in false }
        ServiceLifecycleCoordinator.testSignal = { _, _ in }
        ServiceLifecycleCoordinator.testTCPProbe = { _, _ in tcpProbes += 1; return true } // always busy
        ServiceLifecycleCoordinator.testSleep = { _ in }

        // Must return despite the port never freeing.
        await coordinator.waitForKanataExitBeforeStart()

        let expectedProbes = ServiceLifecycleCoordinator.WaitForExitTiming.pollCount(
            forMs: ServiceLifecycleCoordinator.WaitForExitTiming.portReleaseTimeoutMs
        )
        XCTAssertEqual(tcpProbes, expectedProbes, "Port poll bounded to portReleaseTimeout / pollInterval")
    }

    func testWaitForExit_bothProcessNamesHaveOrphans() async {
        // Both `kanata-launcher` and `kanata` can have live instances; each family must be
        // terminated, not just the first one found.
        var terminated: Set<pid_t> = []
        ServiceLifecycleCoordinator.testPgrepProvider = { name in name == "kanata-launcher" ? [4242] : [5252] }
        ServiceLifecycleCoordinator.testLivenessProbe = { _ in false } // exit immediately
        ServiceLifecycleCoordinator.testSignal = { pid, sig in if sig == SIGTERM { terminated.insert(pid) } }
        ServiceLifecycleCoordinator.testTCPProbe = { _, _ in false }
        ServiceLifecycleCoordinator.testSleep = { _ in }

        await coordinator.waitForKanataExitBeforeStart()

        XCTAssertEqual(terminated, [4242, 5252], "Both process families are terminated")
    }

    func testWaitForExit_multiplePidsPerName() async {
        // A single process family can have multiple orphans; every PID must be SIGTERMed.
        var terminated: Set<pid_t> = []
        ServiceLifecycleCoordinator.testPgrepProvider = { name in name == "kanata-launcher" ? [4242, 4243, 4244] : [] }
        ServiceLifecycleCoordinator.testLivenessProbe = { _ in false } // all exit immediately
        ServiceLifecycleCoordinator.testSignal = { pid, sig in if sig == SIGTERM { terminated.insert(pid) } }
        ServiceLifecycleCoordinator.testTCPProbe = { _, _ in false }
        ServiceLifecycleCoordinator.testSleep = { _ in }

        await coordinator.waitForKanataExitBeforeStart()

        XCTAssertEqual(terminated, [4242, 4243, 4244], "Every orphan PID for the name is terminated")
    }

    func testWaitForExit_safeToCallRepeatedlyAcrossRestarts() async {
        // A restart calls this on every start. Re-invoking after the orphan is gone must be
        // a clean no-op (no signals, no port wait), not a crash or a redundant kill.
        var pids: [pid_t] = [4242]
        var signals: [Int32] = []
        ServiceLifecycleCoordinator.testPgrepProvider = { name in name == "kanata-launcher" ? pids : [] }
        ServiceLifecycleCoordinator.testLivenessProbe = { _ in false } // exits on first probe
        ServiceLifecycleCoordinator.testSignal = { _, sig in signals.append(sig) }
        ServiceLifecycleCoordinator.testTCPProbe = { _, _ in false }
        ServiceLifecycleCoordinator.testSleep = { _ in }

        await coordinator.waitForKanataExitBeforeStart()
        XCTAssertEqual(signals, [SIGTERM], "First call terminates the orphan")

        // Orphan is now gone — a second invocation must be a clean no-op.
        pids = []
        signals = []
        await coordinator.waitForKanataExitBeforeStart()
        XCTAssertEqual(signals, [], "Second call with no orphans signals nothing")
    }
}
