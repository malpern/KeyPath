@testable import KeyPathAppKit
import KeyPathCore
import KeyPathDaemonLifecycle
@testable import KeyPathInstallationWizard
import KeyPathWizardCore
import ServiceManagement
import XCTest

/// The upgrade path from public 1.0.1 (#1353): one administrator prompt removes
/// the kanata daemon and helper, and success needs fresh evidence that none of
/// it is left. The VirtualHID driver is reported, never removed.
@MainActor
final class LegacyPrivilegedRuntimeCleanupTests: KeyPathTestCase {
    private var inspections: [LegacyPrivilegedRuntimeEvidence] = []
    private var inspectCount = 0
    private var batches: [PrivilegedCommandRunner.Batch] = []
    private var unregisterCount = 0
    private var sleeps = 0
    private var batchResult: Result<(exitCode: Int32, output: String), Error> = .success((0, ""))

    private static let installed101 = LegacyPrivilegedRuntimeEvidence(
        loadedServices: ["com.keypath.kanata", "com.keypath.helper"],
        rootProcesses: [SystemProcessMatch(
            pid: 4242,
            command: "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata-launcher --port 37001"
        )],
        leftoverFiles: ["/Library/PrivilegedHelperTools/com.keypath.helper"],
        virtualHID: LegacyVirtualHIDRemnants(driverInstalled: true, karabinerElementsInstalled: false)
    )
    private static let clean = LegacyPrivilegedRuntimeEvidence(
        virtualHID: LegacyVirtualHIDRemnants(driverInstalled: true, karabinerElementsInstalled: false)
    )

    private func makeCleanup() -> LegacyPrivilegedRuntimeCleanup {
        LegacyPrivilegedRuntimeCleanup(dependencies: .init(
            inspect: { [unowned self] in
                inspectCount += 1
                // Repeat the last reading once the script runs out.
                return inspections.isEmpty ? Self.clean : (inspections.count > 1 ? inspections.removeFirst() : inspections[0])
            },
            unregisterRegistrations: { [unowned self] in
                unregisterCount += 1
                return ["unregistered"]
            },
            executeBatch: { [unowned self] batch in
                batches.append(batch)
                return try batchResult.get()
            },
            sleep: { [unowned self] _ in sleeps += 1 }
        ))
    }

    // MARK: - Cleanup

    func testNothingLeftNeedsNoAuthorization() async {
        inspections = [Self.clean]
        let outcome = await makeCleanup().run()
        XCTAssertTrue(outcome.success)
        XCTAssertFalse(outcome.requestedAuthorization)
        XCTAssertTrue(batches.isEmpty, "A Mac without 1.0.1 must never see an administrator prompt")
        XCTAssertEqual(unregisterCount, 0)
    }

    func testOneAuthorizationRemovesTheStackAndWaitsForLaunchdTeardown() async {
        let stillTearingDown = LegacyPrivilegedRuntimeEvidence(loadedServices: ["com.keypath.kanata"])
        inspections = [Self.installed101, stillTearingDown, Self.clean]
        let outcome = await makeCleanup().run()

        XCTAssertTrue(outcome.success, outcome.failureReason ?? "")
        XCTAssertTrue(outcome.requestedAuthorization)
        XCTAssertEqual(batches.count, 1, "The whole cleanup must take one administrator prompt")
        XCTAssertEqual(unregisterCount, 1)
        XCTAssertEqual(inspectCount, 3)
        XCTAssertEqual(sleeps, 1)
        XCTAssertTrue(outcome.after.isClean)

        let script = batches[0].script
        for label in LegacyPrivilegedRuntime.serviceLabels {
            XCTAssertTrue(script.contains("/bin/launchctl bootout system/\(label)"), label)
        }
        for file in LegacyPrivilegedRuntime.systemFiles {
            XCTAssertTrue(script.contains("/bin/rm -f '\(file)'"), file)
        }
        XCTAssertTrue(script.contains("for kp_pid in 4242;"))
        XCTAssertTrue(script.contains("/bin/ps -o command= -p \"$kp_pid\""),
                      "The PID must be re-checked as root before it is signalled")
    }

    func testCancelledAuthorizationIsReportedAsCancelled() async {
        inspections = [Self.installed101]
        batchResult = .success((1, "execution error: User canceled. (-128)"))
        let outcome = await makeCleanup().run()

        XCTAssertFalse(outcome.success)
        XCTAssertFalse(outcome.operationSucceeded)
        XCTAssertTrue(outcome.failureReason?.hasPrefix("Administrator authorization was cancelled.") == true,
                      outcome.failureReason ?? "")
        XCTAssertEqual(sleeps, 0, "A refused batch is not polled as if it were tearing down")
        XCTAssertEqual(batches.count, 1)
    }

    func testFailedBatchIsNeverSuccessEvenIfNothingIsLeft() async {
        inspections = [Self.installed101, Self.clean]
        batchResult = .success((2, "rm: permission denied"))
        let outcome = await makeCleanup().run()
        XCTAssertFalse(outcome.success)
        XCTAssertTrue(outcome.failureReason?.contains("status 2") == true)
    }

    func testThrownExecutorIsFailure() async {
        inspections = [Self.installed101]
        batchResult = .failure(InstallerError.unknownRecipe("Administrator commands are not configured"))
        let outcome = await makeCleanup().run()
        XCTAssertFalse(outcome.success)
        XCTAssertTrue(outcome.failureReason?.contains("not configured") == true)
    }

    func testDaemonStillLoadedAfterTheBatchFailsVerification() async {
        inspections = [Self.installed101, LegacyPrivilegedRuntimeEvidence(loadedServices: ["com.keypath.kanata"])]
        let outcome = await makeCleanup().run()

        XCTAssertFalse(outcome.success)
        XCTAssertTrue(outcome.operationSucceeded)
        XCTAssertTrue(outcome.failureReason?.contains("com.keypath.kanata") == true, outcome.failureReason ?? "")
        XCTAssertEqual(inspectCount, 1 + LegacyPrivilegedRuntimeCleanup.verificationAttempts)
    }

    func testUnreadableServiceStateIsNeverTreatedAsGone() async {
        inspections = [Self.installed101, LegacyPrivilegedRuntimeEvidence(unreadableServices: ["com.keypath.kanata"])]
        let outcome = await makeCleanup().run()
        XCTAssertFalse(outcome.success)
        XCTAssertTrue(outcome.failureReason?.contains("could not check") == true)
    }

    func testVirtualHIDDriverIsReportedButNeverRemoved() async {
        let script = LegacyPrivilegedRuntimeCleanup.batch(stopping: [4242]).script
        XCTAssertFalse(script.contains("systemextensionsctl"))
        XCTAssertFalse(script.contains("org.pqrs"))
        XCTAssertFalse(script.contains("Karabiner-VirtualHIDDevice-Manager"))

        XCTAssertNil(LegacyVirtualHIDRemnants.none.notice)
        let alone = LegacyVirtualHIDRemnants(driverInstalled: true, karabinerElementsInstalled: false)
        XCTAssertTrue(alone.notice?.contains("Upgrading from KeyPath 1.0.1") == true)
        let shared = LegacyVirtualHIDRemnants(driverInstalled: true, karabinerElementsInstalled: true)
        XCTAssertTrue(shared.notice?.contains("Karabiner-Elements uses it") == true)

        inspections = [Self.installed101, Self.clean]
        let outcome = await makeCleanup().run()
        XCTAssertEqual(outcome.virtualHIDNotice, alone.notice)
    }

    func testBatchWithoutRootProcessesHasNoSignalStep() {
        let script = LegacyPrivilegedRuntimeCleanup.batch(stopping: [0, -1]).script
        XCTAssertFalse(script.contains("kp_pid"))
    }

    // MARK: - Live probes

    func testRootProcessFilterTreatsEPERMAsAliveAndSkipsSignalableProcesses() {
        let matches = [101, 102, 103, 0].map { SystemProcessMatch(pid: pid_t($0), command: "x") }
        let root = LegacyPrivilegedRuntimeCleanup.rootProcesses(
            in: matches,
            isAlive: { $0 != 103 },
            canSignal: { $0 == 102 }
        )
        XCTAssertEqual(root.map(\.pid), [101])
    }

    /// ADR-040: ground the real primitives once. launchd (PID 1) is root and
    /// alive, so probing it returns EPERM; this test process is signalable.
    func testRootProcessFilterAgainstRealProcesses() {
        let matches = [SystemProcessMatch(pid: 1, command: "launchd"),
                       SystemProcessMatch(pid: getpid(), command: "test")]
        let root = LegacyPrivilegedRuntimeCleanup.rootProcesses(
            in: matches,
            isAlive: { SystemStateProvider.isProcessAlive(pid: $0) },
            canSignal: { SystemStateProvider.canSignalProcess(pid: $0) }
        )
        XCTAssertEqual(root.map(\.pid), [1])
    }

    func testLiveInspectionReadsLaunchctlExitCodesAndFiles() async {
        let probes = SystemProbeClient(
            processIDs: { _ in [] },
            processMatches: { _ in [SystemProcessMatch(pid: 77, command: "/Library/KeyPath/bin/kanata --cfg x")] },
            launchctlPrint: { target in
                let code: Int32 = switch target {
                case "system/com.keypath.kanata": 0
                case "system/com.keypath.helper": 1
                default: 113
                }
                return LaunchctlPrintEvidence(target: target, exitCode: code, stdout: "", stderr: "")
            },
            processIDsSynchronously: { _ in [] },
            isProcessAlive: { _ in true },
            probeTCPPort: { _, _ in false }
        )
        let present: Set<String> = ["/Library/KeyPath/bin/kanata", LegacyPrivilegedRuntime.karabinerElementsApp,
                                    LegacyPrivilegedRuntime.driverSupportDirectory]
        let evidence = await LegacyPrivilegedRuntimeCleanup.inspectLive(
            provider: SystemStateProvider(probes: probes),
            fileExists: { present.contains($0) },
            isAlive: { _ in true },
            canSignal: { _ in false }
        )
        XCTAssertEqual(evidence.loadedServices, ["com.keypath.kanata"])
        XCTAssertEqual(evidence.unreadableServices, ["com.keypath.helper"])
        XCTAssertEqual(evidence.rootProcesses.map(\.pid), [77])
        XCTAssertEqual(evidence.leftoverFiles, ["/Library/KeyPath/bin/kanata"])
        XCTAssertEqual(evidence.virtualHID, LegacyVirtualHIDRemnants(driverInstalled: true, karabinerElementsInstalled: true))
    }

    // MARK: - InstallerEngine routing

    private func makeEngine(context: SystemContext) -> InstallerEngine {
        InstallerEngine(
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: StubSystemValidator(context: context),
            legacyRuntimeCleanup: makeCleanup()
        )
    }

    func testFixActionRoutesThroughInstallerEngineWithFinalEvidence() async {
        inspections = [Self.installed101, Self.clean]
        let context = SystemContextBuilder(componentsInstalled: true).build()
        let report = await makeEngine(context: context)
            .runSingleAction(.removeLegacyPrivilegedRuntime, using: PrivilegeBroker())

        XCTAssertTrue(report.success, report.failureReason ?? "")
        XCTAssertEqual(report.completionState, .completed)
        XCTAssertEqual(report.finalContext?.snapshotID, context.snapshotID)
        XCTAssertEqual(report.executedRecipes.map(\.recipeID), [InstallerRecipeID.removeLegacyPrivilegedRuntime])
        XCTAssertEqual(batches.count, 1)
    }

    func testEngineReportsVerifiedNoOpWithoutPrompting() async {
        inspections = [Self.clean]
        let result = await makeEngine(context: SystemContextBuilder(componentsInstalled: true).build())
            .removeLegacyPrivilegedRuntime(using: PrivilegeBroker())
        XCTAssertTrue(result.report.success)
        XCTAssertEqual(result.report.completionState, .verifiedNoOp)
        XCTAssertTrue(result.report.executedRecipes.isEmpty)
        XCTAssertTrue(batches.isEmpty)
    }

    func testEngineReportsVerificationFailure() async {
        inspections = [Self.installed101, LegacyPrivilegedRuntimeEvidence(loadedServices: ["com.keypath.kanata"])]
        let result = await makeEngine(context: SystemContextBuilder(componentsInstalled: true).build())
            .removeLegacyPrivilegedRuntime(using: PrivilegeBroker())
        XCTAssertFalse(result.report.success)
        XCTAssertEqual(result.report.completionState, .verificationFailed)
        XCTAssertEqual(result.report.repairTelemetry.first?.postconditionResult, .failed)
    }

    /// The removal is not a recipe: a forged plan naming it still cannot run.
    func testRemovalCannotBeSmuggledInAsARecipe() async {
        let engine = makeEngine(context: SystemContextBuilder(componentsInstalled: true).build())
        let plan = InstallPlan(
            recipes: [ServiceRecipe(id: InstallerRecipeID.removeLegacyPrivilegedRuntime, type: .installComponent)],
            status: .ready, intent: .repair
        )
        let report = await engine.execute(plan: plan, using: PrivilegeBroker())
        XCTAssertFalse(report.success)
        XCTAssertTrue(report.failureReason?.contains("unavailable in the driverless build") == true)
        XCTAssertTrue(batches.isEmpty)
    }

    // MARK: - ServiceManagement unregistration

    func testUnregistersOnlyRegisteredServicesAndToleratesFailure() async {
        let kanata = RecordingSMAppService(failsUnregister: true)
        let helper = RecordingSMAppService(failsUnregister: false)
        let logs = await LegacyServiceRegistrations.unregister(
            statusFor: { $0 == "com.keypath.kanata.plist" ? .enabled : .notFound },
            service: { $0 == "com.keypath.kanata.plist" ? kanata : helper }
        )
        XCTAssertEqual(kanata.unregisterCalls, 1)
        XCTAssertEqual(helper.unregisterCalls, 0)
        XCTAssertTrue(logs.contains { $0.contains("com.keypath.kanata.plist: unregister failed") })
        XCTAssertTrue(logs.contains { $0.contains("com.keypath.helper.plist: not registered") })
    }
}

private final class RecordingSMAppService: SMAppServiceProtocol, @unchecked Sendable {
    let failsUnregister: Bool
    private(set) var unregisterCalls = 0

    init(failsUnregister: Bool) {
        self.failsUnregister = failsUnregister
    }

    var status: SMAppService.Status {
        .notFound
    }

    func register() throws {}
    func unregister() async throws {
        unregisterCalls += 1
        if failsUnregister {
            throw NSError(domain: "test", code: 1)
        }
    }
}
