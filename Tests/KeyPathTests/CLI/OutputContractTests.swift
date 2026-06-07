@testable import KeyPathAppKit
import XCTest

final class OutputContractTests: XCTestCase {
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
            hasConflicts: false,
            timestamp: Date()
        )
        let keys = try jsonKeys(status)
        let required: Set = [
            "isOperational", "helperInstalled", "helperWorking",
            "keyPathAccessibility", "keyPathInputMonitoring",
            "kanataAccessibility", "kanataInputMonitoring",
            "kanataBinaryInstalled", "karabinerDriverInstalled", "vhidDeviceHealthy",
            "kanataRunning", "karabinerDaemonRunning", "vhidHealthy",
            "hasConflicts", "timestamp",
        ]
        XCTAssertTrue(required.isSubset(of: keys), "Missing required keys: \(required.subtracting(keys))")
    }

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

    func testValidationResultJSONShape() throws {
        let result = CLIValidationResult(isValid: true, errors: [])
        let keys = try jsonKeys(result)
        let required: Set = ["errors", "isValid"]
        XCTAssertTrue(required.isSubset(of: keys), "Missing required keys: \(required.subtracting(keys))")
    }

    func testInspectResultJSONShape() throws {
        let json = """
        {"macOSVersion":"15.0","driverCompatible":true,"planStatus":"ready","blockedBy":"helper","plannedRecipes":["step1"]}
        """
        let result = try decoder.decode(CLIInspectResult.self, from: Data(json.utf8))
        let keys = try jsonKeys(result)
        let required: Set = ["driverCompatible", "macOSVersion", "planStatus", "plannedRecipes"]
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
            issues: [issue]
        )

        let keys = try jsonKeys(result)
        let required: Set = [
            "driverCompatible", "issues", "isOperational", "macOSVersion", "planIntent",
            "planStatus", "plannedRecipes", "promptsNeeded", "userActionRequired",
        ]
        XCTAssertTrue(required.isSubset(of: keys), "Missing required keys: \(required.subtracting(keys))")
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
