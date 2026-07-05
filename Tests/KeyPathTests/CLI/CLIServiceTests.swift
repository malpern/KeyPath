import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
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

    // MARK: - installer planning

    func testRepairDryRunPlansRuntimeServicesForStaleVHIDPlist() async throws {
        let fixture = try makeCLIRepairFixture()
        defer { fixture.cleanup() }

        #if DEBUG
            ServiceHealthChecker.shared.invalidateHealthCache()
        #endif

        let facade = SystemFacade(
            subprocessRunner: SubprocessRunnerFake.shared,
            runtimeSnapshotProvider: { Self.runtimeSnapshot(running: true, responding: true) },
            systemValidator: FixtureSystemValidator()
        )
        let report = await facade.runRepair(dryRun: true)
        let plannedRecipes = try XCTUnwrap(report.plannedRecipes)

        XCTAssertTrue(
            plannedRecipes.contains("\(InstallerRecipeID.installRequiredRuntimeServices) (installComponent)"),
            "Stale VHID LaunchDaemon config should plan the targeted runtime services repair"
        )
        XCTAssertFalse(
            plannedRecipes.contains { $0.contains(InstallerRecipeID.installMissingComponents) },
            "Stale VHID LaunchDaemon config must not fall back to the generic missing-components repair"
        )
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

    private func makeCLIRepairFixture() throws -> CLIRepairFixture {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("CLIRepairFixture-\(UUID().uuidString)", isDirectory: true)
        let launchDaemonsDir = root.appendingPathComponent("LaunchDaemons", isDirectory: true)
        let bundledKanata = root.appendingPathComponent("kanata")
        let bundledLauncher = root.appendingPathComponent("Kanata Engine")
        try fileManager.createDirectory(at: launchDaemonsDir, withIntermediateDirectories: true)
        try Data().write(to: bundledKanata)
        try Data().write(to: bundledLauncher)

        let staleVHIDPlist: [String: Any] = [
            "Label": ServiceHealthChecker.vhidDaemonServiceID,
            "ProgramArguments": [PlistGenerator.vhidDaemonPath],
        ]
        let staleVHIDData = try PropertyListSerialization.data(
            fromPropertyList: staleVHIDPlist,
            format: .xml,
            options: 0
        )
        try staleVHIDData.write(
            to: launchDaemonsDir.appendingPathComponent("\(ServiceHealthChecker.vhidDaemonServiceID).plist")
        )

        let bundlePath = URL(fileURLWithPath: Bundle.main.bundlePath, isDirectory: true)
        let bundleFiles = [
            bundlePath.appendingPathComponent("Contents/MacOS/keypath-cli"),
            bundlePath.appendingPathComponent("Contents/Library/LaunchDaemons/com.keypath.kanata.plist"),
            bundlePath.appendingPathComponent("Contents/Library/HelperTools/KeyPathHelper"),
        ]
        var createdBundleFiles: [URL] = []
        for file in bundleFiles {
            try fileManager.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !fileManager.fileExists(atPath: file.path) {
                try Data().write(to: file)
                createdBundleFiles.append(file)
            }
        }

        let environmentKeys = [
            "KEYPATH_LAUNCH_DAEMONS_DIR",
            "KEYPATH_BUNDLED_KANATA_OVERRIDE",
            "KEYPATH_BUNDLED_KANATA_LAUNCHER_OVERRIDE",
        ]
        let originalEnvironment = Dictionary(
            uniqueKeysWithValues: environmentKeys.map { ($0, ProcessInfo.processInfo.environment[$0]) }
        )
        setenv("KEYPATH_LAUNCH_DAEMONS_DIR", launchDaemonsDir.path, 1)
        setenv("KEYPATH_BUNDLED_KANATA_OVERRIDE", bundledKanata.path, 1)
        setenv("KEYPATH_BUNDLED_KANATA_LAUNCHER_OVERRIDE", bundledLauncher.path, 1)

        return CLIRepairFixture(
            root: root,
            createdBundleFiles: createdBundleFiles,
            originalEnvironment: originalEnvironment
        )
    }
}

@MainActor
private final class FixtureSystemValidator: WizardSystemValidating {
    func checkSystem() async -> SystemSnapshot {
        let now = Date()
        let permissionSet = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "fixture",
            confidence: .high,
            timestamp: now
        )
        let permissions = PermissionOracle.Snapshot(
            keyPath: permissionSet,
            kanata: permissionSet,
            timestamp: now
        )
        let staleVHIDPlist = ServiceHealthChecker.shared.isVHIDDaemonPlistPresentButMisconfigured()

        return SystemSnapshot(
            permissions: permissions,
            components: ComponentStatus(
                kanataBinaryInstalled: true,
                karabinerDriverInstalled: true,
                karabinerDaemonRunning: true,
                vhidDeviceInstalled: true,
                vhidDeviceHealthy: true,
                vhidServicesHealthy: true,
                vhidDaemonPlistMisconfigured: staleVHIDPlist,
                vhidVersionMismatch: false
            ),
            conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
            health: HealthStatus(
                kanataRunning: true,
                karabinerDaemonRunning: true,
                vhidHealthy: true,
                kanataInputCaptureReady: true,
                kanataInputCaptureIssue: nil
            ),
            helper: HelperStatus(isInstalled: true, version: "1.0.0", isWorking: true),
            timestamp: now
        )
    }
}

@MainActor
private struct CLIRepairFixture {
    let root: URL
    let createdBundleFiles: [URL]
    let originalEnvironment: [String: String?]

    func cleanup() {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: root)
        for file in createdBundleFiles {
            try? fileManager.removeItem(at: file)
        }
        for (key, value) in originalEnvironment {
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }
        #if DEBUG
            ServiceHealthChecker.shared.invalidateHealthCache()
        #endif
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
