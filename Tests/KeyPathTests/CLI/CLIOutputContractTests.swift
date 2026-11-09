@testable import KeyPathAppKit
import KeyPathCLISupport
import KeyPathCore
@testable import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import XCTest

final class CLIOutputContractTests: KeyPathTestCase {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder = JSONDecoder()

    func testRuleCollectionJSONShape() throws {
        let json = """
        {"id":"test","name":"Test","isEnabled":true,"mappingCount":5,"summary":"Test collection"}
        """
        let collection = try decoder.decode(CLIRuleCollection.self, from: Data(json.utf8))
        let keys = try jsonKeys(collection)
        XCTAssertEqual(keys, ["id", "isEnabled", "mappingCount", "name", "summary"])
    }

    func testApplyResultJSONShape() throws {
        let changeset = CLIApplyChangeset(enabledCollections: ["Home Row Mods"], disabledCollections: [], customRules: ["caps → esc"])
        let result = CLIApplyResult(collectionsCount: 3, enabledCount: 2, customRulesCount: 1, reloadSuccess: true, changeset: changeset)
        let keys = try jsonKeys(result)
        let required: Set = ["collectionsCount", "customRulesCount", "enabledCount", "reloadSuccess", "changeset"]
        XCTAssertTrue(required.isSubset(of: keys), "Missing required keys: \(required.subtracting(keys))")
    }

    func testInstallerReportJSONShape() throws {
        let json = """
        {"success":true,"failureReason":"test reason","steps":[{"name":"test","success":true,"error":"err"}],"fastRepair":false}
        """
        let report = try decoder.decode(CLIInstallerReport.self, from: Data(json.utf8))
        let keys = try jsonKeys(report)
        let required: Set = ["fastRepair", "steps", "success"]
        XCTAssertTrue(required.isSubset(of: keys), "Missing required keys: \(required.subtracting(keys))")
    }

    func testInstallerReportRepairMetadataJSONShape() throws {
        let issue = CLISystemIssue(
            title: "KeyPath runtime needs keyboard access permission",
            category: "permissions",
            action: "Quit and reopen KeyPath",
            canAutoFix: false,
            remediationURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        let report = CLIInstallerReport(
            success: false,
            failureReason: "Repair requires user action",
            steps: [],
            fastRepair: false,
            dryRun: true,
            userActionRequired: true,
            issues: [issue],
            plannedRecipes: ["reinstall-privileged-helper (installService)"],
            unmetRequirements: [],
            logs: nil
        )

        let keys = try jsonKeys(report)
        let required: Set = [
            "dryRun", "failureReason", "fastRepair", "issues", "plannedRecipes",
            "steps", "success", "unmetRequirements", "userActionRequired",
        ]
        XCTAssertTrue(required.isSubset(of: keys), "Missing required keys: \(required.subtracting(keys))")

        let data = try encoder.encode(report)
        let decoded = try decoder.decode(CLIInstallerReport.self, from: data)
        XCTAssertEqual(decoded.issues?.first?.category, "permissions")
        XCTAssertEqual(
            decoded.issues?.first?.remediationURL,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func testInstallerReportMarksActivationApprovalTimeoutAsUserActionRequired() {
        let context = SystemContextBuilder.degradedRepair()
        let planID = UUID()
        let plan = InstallPlan(
            id: planID,
            sourceSnapshotID: context.snapshotID,
            recipes: [],
            status: .ready,
            intent: .repair
        )
        let runID = UUID()
        let afterSnapshotID = UUID()
        let installerReport = InstallerReport(
            runID: runID,
            planID: planID,
            beforeSnapshotID: context.snapshotID,
            afterSnapshotID: afterSnapshotID,
            success: false,
            completionState: .verificationFailed,
            failureReason: "VHID Manager activation failed: timed out after 20s. VirtualHID activation may be waiting for macOS approval. Open System Settings > Privacy & Security and approve the Karabiner VirtualHIDDevice system extension, then retry repair."
        )

        let report = CLIInstallerReport(
            from: installerReport,
            initialContext: context,
            finalContext: nil,
            plan: plan,
            title: "Repair"
        )

        XCTAssertEqual(report.userActionRequired, true)
        XCTAssertEqual(report.runID, runID.uuidString)
        XCTAssertEqual(report.planID, planID.uuidString)
        XCTAssertEqual(report.beforeSnapshotID, context.snapshotID.uuidString)
        XCTAssertEqual(report.afterSnapshotID, afterSnapshotID.uuidString)
        XCTAssertEqual(report.completionState, "verification-failed")
    }

    func testInstallerReportPreservesStructuredAwaitingApprovalOutcome() {
        let context = SystemContextBuilder(
        ).build()
        let plan = InstallPlan(
            sourceSnapshotID: context.snapshotID,
            recipes: [],
            status: .ready,
            intent: .install
        )
        let installerReport = InstallerReport(
            planID: plan.id,
            beforeSnapshotID: context.snapshotID,
            afterSnapshotID: context.snapshotID,
            success: true,
            completionState: .awaitingApproval,
            finalContext: context
        )

        let report = CLIInstallerReport(
            from: installerReport,
            initialContext: context,
            finalContext: context,
            plan: plan,
            title: "Install"
        )

        XCTAssertTrue(report.success)
        XCTAssertNil(report.failureReason)
        XCTAssertEqual(report.userActionRequired, true)
        XCTAssertEqual(report.completionState, "awaiting-approval")
    }

    func testDryRunBlockedPlanReportsStructuredBlockedState() {
        let context = SystemContextBuilder.degradedRepair()
        let requirement = Requirement(name: "Manual approval", status: .blocked)
        let plan = InstallPlan(
            sourceSnapshotID: context.snapshotID,
            recipes: [],
            status: .blocked(requirement: requirement),
            intent: .repair,
            blockedBy: requirement
        )

        let report = CLIInstallerReport(dryRunPlan: plan, context: context, title: "Repair")

        XCTAssertFalse(report.success)
        XCTAssertEqual(report.completionState, "blocked")
    }

    func testInstallerReportLinksTerminalConfigFailureToTroubleshooting() {
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            servicesHealthy: false,
            kanataRunning: false,
            kanataInputCaptureReady: true,
            componentsInstalled: true
        ).build()
        let services = HealthStatus(
            kanataRunning: false,
            kanataInputCaptureReady: true,
            configParseError: "expected defcfg"
        )
        let configContext = SystemContext(
            permissions: context.permissions,
            services: services,
            conflicts: context.conflicts,
            components: context.components,
            system: context.system,
            timestamp: context.timestamp
        )
        let report = CLIInstallerReport(
            dryRunPlan: InstallPlan(recipes: [], status: .ready, intent: .repair),
            context: configContext,
            title: "Repair"
        )

        let issue = report.issues?.first { $0.title == "Configuration error prevents remapping" }
        XCTAssertEqual(issue?.remediationURL, KeyPathConstants.URLs.configurationTroubleshooting)
    }

    func testValidationResultJSONShape() throws {
        let result = CLIValidationResult(isValid: true, errors: [])
        let keys = try jsonKeys(result)
        let required: Set = ["errors", "isValid"]
        XCTAssertTrue(required.isSubset(of: keys), "Missing required keys: \(required.subtracting(keys))")
    }

    func testInspectResultRepairMetadataJSONShape() throws {
        let issue = CLISystemIssue(
            title: "Privileged Helper unhealthy",
            category: "helper",
            action: "Reinstall the privileged helper",
            canAutoFix: true
        )
        let result = CLIInspectResult(
            macOSVersion: "26.5.0",
            planStatus: "ready",
            blockedBy: nil,
            plannedRecipes: ["reinstall-privileged-helper (installService)"],
            planIntent: "repair",
            isOperational: false,
            userActionRequired: false,
            promptsNeeded: true,
            issues: [issue],
            stateMatrixRow: InstallerStateMatrixRow.sessionRuntimeStopped.rawValue,
            stateMatrixPlan: [
                InstallerStateMatrixAction.restartOrRecoverKanataRuntime.rawValue,
            ]
        )

        let keys = try jsonKeys(result)
        let required: Set = [
            "issues", "isOperational", "macOSVersion", "planIntent",
            "planStatus", "plannedRecipes", "promptsNeeded", "stateMatrixPlan",
            "stateMatrixRow", "userActionRequired",
        ]
        XCTAssertTrue(required.isSubset(of: keys), "Missing required keys: \(required.subtracting(keys))")

        let data = try encoder.encode(result)
        let decoded = try decoder.decode(CLIInspectResult.self, from: data)
        XCTAssertEqual(decoded.stateMatrixRow, InstallerStateMatrixRow.sessionRuntimeStopped.rawValue)
        XCTAssertEqual(decoded.stateMatrixPlan, [InstallerStateMatrixAction.restartOrRecoverKanataRuntime.rawValue])
    }

    func testPermissionGuidanceUsesOSPaneNameWithoutChangingPolicyOrDeepLink() {
        let name = "Device Control and Data Access"
        let presentation = AccessibilityPermissionPresentation()
        let contexts = [
            sessionContext(appAX: .denied),
            explicitContext(
                permissionsStatus: .denied,
                servicesHealthy: true, componentsInstalled: true
            )
        ]
        for context in contexts {
            let issues = SystemFacade.issues(from: context, accessibility: presentation)
            let issue = issues.first { $0.title == "KeyPath needs \(name) permission" }
            XCTAssertEqual(issue?.action, "Open KeyPath.app and grant \(name) in System Settings > Privacy & Security > \(name)")
            XCTAssertEqual(issue?.remediationURL, "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            XCTAssertEqual(issue?.severity, .error)
            XCTAssertEqual(issue?.requiresUserAction, true)
            XCTAssertFalse(SystemFacade.isOperational(context))
        }
    }

    func testPermissionIssuesPreserveTriModeSemantics() {
        let granted = explicitContext(
            permissionsStatus: .granted,
            servicesHealthy: true,
            componentsInstalled: true
        )
        XCTAssertFalse(SystemFacade.issues(from: granted).contains { $0.category == "permissions" })
        XCTAssertTrue(SystemFacade.isOperational(granted))

        let denied = explicitContext(
            permissionsStatus: .denied,
            servicesHealthy: true,
            componentsInstalled: true
        )
        let deniedIssues = SystemFacade.issues(from: denied).filter { $0.category == "permissions" }
        XCTAssertTrue(deniedIssues.contains { $0.severity == .error })
        XCTAssertTrue(deniedIssues.contains(where: \.requiresUserAction))
        XCTAssertTrue(deniedIssues.contains { $0.title == "KeyPath needs \(AccessibilityPermissionPresentation.current.name) permission" })
        XCTAssertFalse(deniedIssues.contains { $0.title.contains("Input Monitoring") })
        XCTAssertFalse(SystemFacade.isOperational(denied))

        let unknown = explicitContext(
            permissionsStatus: .unknown,
            servicesHealthy: true,
            componentsInstalled: true
        )
        let unknownIssues = SystemFacade.issues(from: unknown).filter { $0.category == "permissions" }
        XCTAssertTrue(unknownIssues.allSatisfy { $0.severity == .warning })
        XCTAssertFalse(unknownIssues.contains(where: \.requiresUserAction))
        XCTAssertTrue(unknownIssues.contains {
            $0.title == "KeyPath \(AccessibilityPermissionPresentation.current.name) permission not verified"
        })
        XCTAssertFalse(unknownIssues.contains { $0.title.contains(" needs ") })
        XCTAssertFalse(SystemFacade.isOperational(unknown))
    }

    func testJSONRoundTripsPreserveKeys() throws {
        let changeset = CLIApplyChangeset(enabledCollections: ["A"], disabledCollections: ["B"], customRules: ["caps → esc"])
        let result = CLIApplyResult(collectionsCount: 5, enabledCount: 3, customRulesCount: 2, reloadSuccess: true, changeset: changeset)
        let data = try encoder.encode(result)
        let decoded = try decoder.decode(CLIApplyResult.self, from: data)
        XCTAssertEqual(decoded.collectionsCount, 5)
        XCTAssertEqual(decoded.enabledCount, 3)
        XCTAssertEqual(decoded.customRulesCount, 2)
        XCTAssertTrue(decoded.reloadSuccess)
        XCTAssertEqual(decoded.changeset?.enabledCollections, ["A"])
        XCTAssertEqual(decoded.changeset?.customRules, ["caps → esc"])
    }

    func testSessionIsOperationalWhenRuntimeIsReady() {
        let context = sessionContext()
        XCTAssertTrue(SystemFacade.isOperational(context))
        let issues = SystemFacade.issues(from: context)
        XCTAssertTrue(issues.isEmpty)
    }

    func testSessionDeniedRuntimeKeyAccessAsksForRelaunch() {
        let context = sessionContext(runtimeKeyAccess: .denied)
        XCTAssertFalse(SystemFacade.isOperational(context))
        let issues = SystemFacade.issues(from: context)
        let runtimeIssues = issues.filter { $0.title == "KeyPath runtime needs keyboard access permission" }
        XCTAssertEqual(runtimeIssues.count, 1)
        XCTAssertEqual(
            runtimeIssues.first?.action,
            "Quit and reopen KeyPath so it can use \(AccessibilityPermissionPresentation.current.name)."
        )
        XCTAssertFalse(issues.contains { $0.title.contains("Input Monitoring") })
        XCTAssertFalse(issues.contains { $0.title.contains("Kanata") || $0.category == "helper" })
    }

    func testSessionUnknownPermissionIsNotReadyAndNeverRequestsFullDiskAccess() {
        let context = sessionContext(appAX: .unknown, runtimeKeyAccess: .unknown)
        XCTAssertFalse(SystemFacade.isOperational(context))
        let issues = SystemFacade.issues(from: context)
        XCTAssertEqual(issues.first?.title, "KeyPath \(AccessibilityPermissionPresentation.current.name) permission not verified")
        XCTAssertTrue(issues.contains { $0.action.contains("active session") })
        XCTAssertFalse(issues.contains {
            $0.action.contains("Full Disk Access") || $0.remediationURL == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        })
    }

    func testSessionAccessibilityRemediationComesBeforeRuntimeAccess() {
        let issues = SystemFacade.issues(from: sessionContext(appAX: .denied, runtimeKeyAccess: .denied))
        XCTAssertEqual(issues.first?.title, "KeyPath needs \(AccessibilityPermissionPresentation.current.name) permission")
        XCTAssertEqual(issues.filter { $0.title.contains(AccessibilityPermissionPresentation.current.name) }.count, 1)
        XCTAssertFalse(issues.contains { $0.title.contains("Kanata Engine") })
    }

    func testSessionConflictsRequireManualResolutionAndNeverAdvertiseDriverRepair() {
        let context = sessionContext(conflicts: [.karabinerGrabberRunning(pid: 123)])
        XCTAssertFalse(SystemFacade.isOperational(context))
        let issues = SystemFacade.issues(from: context)
        let conflict = issues.first { $0.category == "conflict" }
        XCTAssertEqual(conflict?.canAutoFix, false)
        XCTAssertTrue(conflict?.action.contains("manually") ?? false)
        XCTAssertFalse(issues.contains { $0.category == "helper" || $0.action.contains("Install the bundled VirtualHID") })
    }

    func testSessionReadinessRequiresResponsiveRuntimeAndPreservesConfigDiagnostics() {
        let unresponsive = sessionContext(responding: false)
        XCTAssertFalse(SystemFacade.isOperational(unresponsive))
        XCTAssertTrue(SystemFacade.issues(from: unresponsive).contains { $0.title == "KeyPath session is not responding" })
        let invalid = sessionContext(running: false, responding: false, configError: "unsupported media action")
        let issue = SystemFacade.issues(from: invalid).first { $0.category == "configuration" }
        XCTAssertEqual(issue?.action, "unsupported media action")
        XCTAssertEqual(issue?.remediationURL, KeyPathConstants.URLs.configurationTroubleshooting)
    }

    func testSessionRepairArtifactsExcludePrivilegedPayload() {
        let paths = SystemFacade.sessionRepairRequiredPaths(bundlePath: "/tmp/KeyPath.app")
        XCTAssertEqual(paths.count, 3)
        XCTAssertTrue(paths.contains("/tmp/KeyPath.app/Contents/MacOS/keypath-cli"))
        XCTAssertTrue(paths.contains { $0.hasSuffix("libkeypath_kanata_host_bridge.dylib") })
        XCTAssertFalse(paths.contains { $0.contains("HelperTools") || $0.contains("LaunchDaemons") || $0.hasSuffix("kanata-launcher") })
    }

    private func sessionContext(
        appAX: PermissionOracle.Status = .granted,
        runtimeKeyAccess: PermissionOracle.Status = .granted,
        running: Bool = true, responding: Bool = true,
        configError: String? = nil, conflicts: [SystemConflict] = []
    ) -> SystemContext {
        let now = Date()
        let permissions = PermissionOracle.Snapshot.fixture(
            accessibility: appAX, runtimeKeyAccess: runtimeKeyAccess, source: "test.session", timestamp: now
        )
        let components = ComponentStatus(
            kanataBinaryInstalled: true, requiredRuntimePayloadPresent: true
        )
        let health = HealthStatus(
            kanataProcessRunning: running, kanataTCPResponding: responding,
            kanataRunning: running && responding, configParseError: configError
        )
        return SystemContext(snapshot: SystemSnapshot(
            permissions: permissions, components: components,
            conflicts: ConflictStatus(conflicts: conflicts, canAutoResolve: true),
            health: health, timestamp: now
        ))
    }

    // MARK: - Helpers

    private func jsonKeys(_ value: some Encodable) throws -> Set<String> {
        let data = try encoder.encode(value)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return Set(dict.keys)
    }

    /// A context built directly from permission, service and component facts,
    /// independent of the default session context builder.
    private func explicitContext(
        permissionsStatus: PermissionOracle.Status = .granted,
        servicesHealthy: Bool = true,
        kanataInputCaptureReady: Bool = true,
        kanataInputCaptureIssue: String? = nil,
        componentsInstalled: Bool = true
    ) -> SystemContext {
        let now = Date()
        let permissions = PermissionOracle.Snapshot.fixture(
            accessibility: permissionsStatus, runtimeKeyAccess: permissionsStatus,
            source: "test.explicit", timestamp: now
        )
        let components = ComponentStatus(
            kanataBinaryInstalled: componentsInstalled,
            requiredRuntimePayloadPresent: componentsInstalled
        )
        let services = HealthStatus(
            kanataRunning: servicesHealthy,
            kanataInputCaptureReady: kanataInputCaptureReady,
            kanataInputCaptureIssue: kanataInputCaptureIssue
        )
        return SystemContext(snapshot: SystemSnapshot(
            permissions: permissions, components: components, conflicts: .empty,
            health: services, compatibility: SystemCompatibilityStatus(macOSVersion: "27.0"),
            timestamp: now
        ))
    }
}
