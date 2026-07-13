import Foundation
import KeyPathCLISupport
import KeyPathInstallationWizard
import XCTest

final class CLIReportModelsTests: XCTestCase {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder = JSONDecoder()

    func testStatusJSONShape() throws {
        let status = CLIStatusResult(
            isOperational: true,
            helperInstalled: true,
            helperWorking: true,
            helperVersion: "1.0",
            helperExpectedVersion: "1.1.0",
            helperFreshness: "stale",
            keyPathAccessibility: true,
            keyPathInputMonitoring: true,
            kanataAccessibility: true,
            kanataInputMonitoring: true,
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            vhidDeviceHealthy: true,
            kanataRunning: true,
            karabinerDaemonRunning: true,
            vhidHealthy: true,
            activeRuntimePathTitle: "test",
            activeRuntimePathDetail: "detail",
            kanataServiceFreshness: "stale",
            kanataExpectedIdentity: "com.keypath.KeyPath build 4 · Contents/Library/KeyPath/kanata-launcher",
            hasConflicts: false,
            timestamp: Date()
        )
        let keys = try jsonKeys(status)
        let required: Set = [
            "isOperational", "helperInstalled", "helperWorking",
            "helperExpectedVersion", "helperFreshness",
            "keyPathAccessibility", "keyPathInputMonitoring",
            "kanataAccessibility", "kanataInputMonitoring",
            "kanataBinaryInstalled", "karabinerDriverInstalled", "vhidDeviceHealthy",
            "kanataRunning", "karabinerDaemonRunning", "vhidHealthy",
            "kanataServiceFreshness", "kanataExpectedIdentity",
            "hasConflicts", "timestamp",
        ]
        XCTAssertTrue(required.isSubset(of: keys), "Missing required keys: \(required.subtracting(keys))")
    }

    func testInstallerReportRepairTelemetryJSONShape() throws {
        let runID = UUID()
        let planID = UUID()
        let beforeSnapshotID = UUID()
        let afterSnapshotID = UUID()
        let installerReport = InstallerReport(
            runID: runID,
            planID: planID,
            beforeSnapshotID: beforeSnapshotID,
            afterSnapshotID: afterSnapshotID,
            success: true,
            completionState: .completed,
            executedRecipes: [
                RecipeResult(recipeID: InstallerRecipeID.createConfigDirectories, success: true),
            ],
            repairTelemetry: [
                InstallerRepairTelemetryEvent(
                    timestamp: Date(timeIntervalSince1970: 0),
                    runID: runID,
                    planID: planID,
                    beforeSnapshotID: beforeSnapshotID,
                    afterSnapshotID: afterSnapshotID,
                    trigger: .executePlan,
                    intent: "repair",
                    stateMatrixRow: InstallerStateMatrixRow.freshInstallMissingComponents.rawValue,
                    stateMatrixPlan: [InstallerStateMatrixAction.installMissingComponents.rawValue],
                    action: InstallerRecipeID.createConfigDirectories,
                    recipeID: InstallerRecipeID.createConfigDirectories,
                    recipeType: "install-component",
                    postconditionResult: .succeeded
                ),
            ]
        )

        let report = CLIInstallerReport(from: installerReport)
        let keys = try jsonKeys(report)
        XCTAssertTrue(keys.contains("repairTelemetry"))

        let data = try encoder.encode(report)
        let decoded = try decoder.decode(CLIInstallerReport.self, from: data)
        let event = try XCTUnwrap(decoded.repairTelemetry?.first)
        XCTAssertEqual(decoded.runID, runID.uuidString)
        XCTAssertEqual(decoded.planID, planID.uuidString)
        XCTAssertEqual(decoded.beforeSnapshotID, beforeSnapshotID.uuidString)
        XCTAssertEqual(decoded.afterSnapshotID, afterSnapshotID.uuidString)
        XCTAssertEqual(decoded.completionState, "completed")
        XCTAssertNil(decoded.userActionRequired)
        XCTAssertEqual(event.runID, runID.uuidString)
        XCTAssertEqual(event.planID, planID.uuidString)
        XCTAssertEqual(event.beforeSnapshotID, beforeSnapshotID.uuidString)
        XCTAssertEqual(event.afterSnapshotID, afterSnapshotID.uuidString)
        XCTAssertEqual(event.trigger, "execute-plan")
        XCTAssertEqual(event.intent, "repair")
        XCTAssertEqual(event.stateMatrixRow, InstallerStateMatrixRow.freshInstallMissingComponents.rawValue)
        XCTAssertEqual(event.stateMatrixPlan, [InstallerStateMatrixAction.installMissingComponents.rawValue])
        XCTAssertEqual(event.action, InstallerRecipeID.createConfigDirectories)
        XCTAssertEqual(event.recipeID, InstallerRecipeID.createConfigDirectories)
        XCTAssertEqual(event.recipeType, "install-component")
        XCTAssertEqual(event.postconditionResult, "succeeded")
        XCTAssertNil(event.error)
    }

    func testInstallerReportExposesExplicitRecoveryAction() {
        let installerReport = InstallerReport(
            success: false,
            failureReason: "The system helper could not be repaired.",
            logs: ["helper repair failed"],
            recommendedRecovery: .emergencyCleanup
        )

        let report = CLIInstallerReport(from: installerReport)

        XCTAssertEqual(report.recommendedRecovery, "emergency-cleanup")
        XCTAssertEqual(report.userActionRequired, true)
        XCTAssertEqual(report.logs, ["helper repair failed"])
    }

    func testInspectResultJSONShape() throws {
        let json = """
        {"macOSVersion":"15.0","driverCompatible":true,"planStatus":"ready","blockedBy":"helper","plannedRecipes":["step1"]}
        """
        let result = try decoder.decode(CLIInspectResult.self, from: Data(json.utf8))
        let keys = try jsonKeys(result)
        let required: Set = ["driverCompatible", "macOSVersion", "planStatus", "plannedRecipes"]
        XCTAssertTrue(required.isSubset(of: keys), "Missing required keys: \(required.subtracting(keys))")
        XCTAssertNil(result.stateMatrixRow)
        XCTAssertNil(result.stateMatrixPlan)
    }

    private func jsonKeys(_ value: some Encodable) throws -> Set<String> {
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let object else { return [] }
        return Set(object.keys)
    }
}
