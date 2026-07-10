@testable import KeyPathAppKit
import KeyPathCLISupport
import KeyPathCore
@testable import KeyPathInstallationWizard
import KeyPathWizardCore
import XCTest

final class CLIOutputContractTests: XCTestCase {
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
            title: "Kanata needs Input Monitoring permission",
            category: "permissions",
            action: "Open System Settings",
            canAutoFix: false,
            remediationURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
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
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
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
            helperReady: false,
            helperRequiresApproval: true,
            loginItemsApprovalRequired: true
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

    func testInstallerReportLinksTerminalInputCaptureFailureToTroubleshooting() {
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: true,
            kanataInputCaptureReady: false,
            kanataInputCaptureIssue: ServiceHealthChecker.inputCaptureGrabFailureReason,
            componentsInstalled: true
        ).build()
        let report = CLIInstallerReport(
            dryRunPlan: InstallPlan(recipes: [], status: .ready, intent: .repair),
            context: context,
            title: "Repair"
        )

        let issue = report.issues?.first { $0.title == "Kanata cannot capture keyboard input" }
        XCTAssertEqual(issue?.remediationURL, KeyPathConstants.URLs.terminalInputCaptureTroubleshooting)
    }

    func testInstallerReportLinksTerminalConfigFailureToTroubleshooting() {
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: false,
            kanataRunning: false,
            kanataInputCaptureReady: true,
            componentsInstalled: true
        ).build()
        let services = HealthStatus(
            kanataRunning: false,
            karabinerDaemonRunning: true,
            vhidHealthy: true,
            kanataInputCaptureReady: true,
            configParseError: "expected defcfg"
        )
        let configContext = SystemContext(
            permissions: context.permissions,
            services: services,
            conflicts: context.conflicts,
            components: context.components,
            helper: context.helper,
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

    func testInstallerReportLinksMissingBundledKanataToTroubleshooting() {
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: false,
            kanataInputCaptureReady: true,
            componentsInstalled: false
        ).build()
        let report = CLIInstallerReport(
            dryRunPlan: InstallPlan(recipes: [], status: .ready, intent: .repair),
            context: context,
            title: "Repair"
        )

        let issue = report.issues?.first { $0.title == "Kanata binary not installed" }
        XCTAssertEqual(issue?.remediationURL, KeyPathConstants.URLs.bundledKanataTroubleshooting)
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
            driverCompatible: true,
            planStatus: "ready",
            blockedBy: nil,
            plannedRecipes: ["reinstall-privileged-helper (installService)"],
            planIntent: "repair",
            isOperational: false,
            userActionRequired: false,
            promptsNeeded: true,
            issues: [issue],
            stateMatrixRow: InstallerStateMatrixRow.helperMissing.rawValue,
            stateMatrixPlan: [
                InstallerStateMatrixAction.installHelper.rawValue,
            ]
        )

        let keys = try jsonKeys(result)
        let required: Set = [
            "driverCompatible", "issues", "isOperational", "macOSVersion", "planIntent",
            "planStatus", "plannedRecipes", "promptsNeeded", "stateMatrixPlan",
            "stateMatrixRow", "userActionRequired",
        ]
        XCTAssertTrue(required.isSubset(of: keys), "Missing required keys: \(required.subtracting(keys))")

        let data = try encoder.encode(result)
        let decoded = try decoder.decode(CLIInspectResult.self, from: data)
        XCTAssertEqual(decoded.stateMatrixRow, InstallerStateMatrixRow.helperMissing.rawValue)
        XCTAssertEqual(decoded.stateMatrixPlan, [InstallerStateMatrixAction.installHelper.rawValue])
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

    // MARK: - Helpers

    private func jsonKeys(_ value: some Encodable) throws -> Set<String> {
        let data = try encoder.encode(value)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return Set(dict.keys)
    }
}
