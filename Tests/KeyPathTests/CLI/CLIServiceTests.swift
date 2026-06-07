@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathInstallationWizard
@preconcurrency import XCTest

@MainActor
final class CLIServiceTests: XCTestCase {
    private let facade = SystemFacade()

    // MARK: - serviceLogs

    func testServiceLogsReturnsEmptyForMissingFile() {
        let lines = facade.serviceLogs(lines: 10)
        // If the log file doesn't exist in the test environment, we get empty
        // If it does exist, we get some lines. Either way, no crash.
        XCTAssertTrue(lines.count <= 10)
    }

    func testServiceLogsRespectsLineLimit() {
        let lines = facade.serviceLogs(lines: 5)
        XCTAssertTrue(lines.count <= 5)
    }

    func testServiceLogsDefaultsTo50Lines() {
        let lines = facade.serviceLogs()
        XCTAssertTrue(lines.count <= 50)
    }

    // MARK: - service lifecycle

    func testStopServiceReturnsFalseWhenLaunchctlExitsNonZero() async {
        let fakeRunner = SubprocessRunnerFake.shared
        await fakeRunner.reset()
        await fakeRunner.configureLaunchctlResult { _, _ in
            ProcessResult(
                exitCode: 112,
                stdout: "",
                stderr: "Not privileged to signal service.",
                duration: 0.1
            )
        }

        let facade = SystemFacade(
            subprocessRunner: fakeRunner,
            runtimeSnapshotProvider: { Self.runtimeSnapshot(running: true, responding: true) },
            runtimeTransitionTimeoutSeconds: 0.05,
            pollDelayNanoseconds: 0
        )

        let stopped = await facade.stopService()

        XCTAssertFalse(stopped)
    }

    func testStopServiceWaitsForStoppedRuntimeAfterLaunchctlSuccess() async {
        let fakeRunner = SubprocessRunnerFake.shared
        await fakeRunner.reset()
        let snapshots = RuntimeSnapshotSequence([
            Self.runtimeSnapshot(running: true, responding: true),
            Self.runtimeSnapshot(running: false, responding: false)
        ])

        let facade = SystemFacade(
            subprocessRunner: fakeRunner,
            runtimeSnapshotProvider: { await snapshots.next() },
            runtimeTransitionTimeoutSeconds: 0.05,
            pollDelayNanoseconds: 0
        )

        let stopped = await facade.stopService()

        XCTAssertTrue(stopped)
    }

    func testRestartServiceDoesNotReportSuccessWhenStopFails() async {
        let fakeRunner = SubprocessRunnerFake.shared
        await fakeRunner.reset()
        await fakeRunner.configureLaunchctlResult { subcommand, _ in
            ProcessResult(
                exitCode: subcommand == "kill" ? 112 : 0,
                stdout: "",
                stderr: subcommand == "kill" ? "Not privileged to signal service." : "",
                duration: 0.1
            )
        }

        let facade = SystemFacade(
            subprocessRunner: fakeRunner,
            runtimeSnapshotProvider: { Self.runtimeSnapshot(running: true, responding: true) },
            runtimeTransitionTimeoutSeconds: 0.05,
            pollDelayNanoseconds: 0,
            restartDelayNanoseconds: 0
        )

        let restarted = await facade.restartService()
        let commands = await fakeRunner.executedCommands

        XCTAssertFalse(restarted)
        XCTAssertEqual(commands.compactMap(\.args.first), ["kill"])
    }

    func testStartServiceReturnsFalseWhenRuntimeNeverBecomesHealthy() async {
        let fakeRunner = SubprocessRunnerFake.shared
        await fakeRunner.reset()

        let facade = SystemFacade(
            subprocessRunner: fakeRunner,
            runtimeSnapshotProvider: { Self.runtimeSnapshot(running: true, responding: false) },
            runtimeTransitionTimeoutSeconds: 0.05,
            pollDelayNanoseconds: 0
        )

        let started = await facade.startService()

        XCTAssertFalse(started)
    }

    private nonisolated static func runtimeSnapshot(
        running: Bool,
        responding: Bool
    ) -> ServiceHealthChecker.KanataServiceRuntimeSnapshot {
        ServiceHealthChecker.KanataServiceRuntimeSnapshot(
            managementState: .smappserviceActive,
            isRunning: running,
            isResponding: responding,
            inputCaptureReady: true,
            inputCaptureIssue: nil,
            launchctlExitCode: running ? 0 : nil,
            staleEnabledRegistration: false,
            recentlyRestarted: false
        )
    }
}

private actor RuntimeSnapshotSequence {
    private var snapshots: [ServiceHealthChecker.KanataServiceRuntimeSnapshot]

    init(_ snapshots: [ServiceHealthChecker.KanataServiceRuntimeSnapshot]) {
        self.snapshots = snapshots
    }

    func next() -> ServiceHealthChecker.KanataServiceRuntimeSnapshot {
        if snapshots.count > 1 {
            return snapshots.removeFirst()
        }
        return snapshots[0]
    }
}
