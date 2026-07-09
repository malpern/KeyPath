import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCLI
import KeyPathCLISupport
import KeyPathRulesCore
import XCTest

final class CLIOutputSnapshotTests: XCTestCase {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let fixedDate = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!

    // MARK: - CLIRuleCollection

    func testRuleCollectionSnapshot() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"Home Row Mods","isEnabled":true,"mappingCount":4,"summary":"ASDF mods"}
        """
        let value = try decoder.decode(CLIRuleCollection.self, from: Data(json.utf8))
        try assertSnapshot(value, expected: """
        {
          "id" : "00000000-0000-0000-0000-000000000001",
          "isEnabled" : true,
          "mappingCount" : 4,
          "name" : "Home Row Mods",
          "summary" : "ASDF mods"
        }
        """)
    }

    // MARK: - CLIApplyResult

    func testApplyResultSnapshot() throws {
        let changeset = CLIApplyChangeset(
            enabledCollections: ["Home Row Mods"],
            disabledCollections: ["Vim Navigation"],
            customRules: ["caps → esc"]
        )
        let value = CLIApplyResult(
            collectionsCount: 5,
            enabledCount: 3,
            customRulesCount: 2,
            reloadSuccess: true,
            changeset: changeset
        )
        try assertSnapshot(value, expected: """
        {
          "changeset" : {
            "customRules" : [
              "caps → esc"
            ],
            "disabledCollections" : [
              "Vim Navigation"
            ],
            "enabledCollections" : [
              "Home Row Mods"
            ]
          },
          "collectionsCount" : 5,
          "customRulesCount" : 2,
          "enabledCount" : 3,
          "reloadSuccess" : true
        }
        """)
    }

    // MARK: - CLIValidationResult

    func testValidationResultSnapshot() throws {
        let value = CLIValidationResult(isValid: false, errors: ["Unknown key: xyz", "Missing deflayer"])
        try assertSnapshot(value, expected: """
        {
          "errors" : [
            "Unknown key: xyz",
            "Missing deflayer"
          ],
          "isValid" : false
        }
        """)
    }

    // MARK: - CLIHrmStats

    func testHrmStatsSnapshot() throws {
        let value = CLIHrmStats(totalDecisions: 100, tapCount: 60, holdCount: 40)
        try assertSnapshot(value, expected: """
        {
          "holdCount" : 40,
          "tapCount" : 60,
          "totalDecisions" : 100
        }
        """)
    }

    // MARK: - RuleAddResult (created)

    func testRuleAddCreatedSnapshot() throws {
        let rule = CustomRule(input: "caps", action: .keystroke(key: "esc"), createdAt: fixedDate)
        let detail = CLIRuleDetail(from: rule)
        let value = RuleAddResult.created(detail)
        try assertSnapshot(value, expected: """
        {
          "rule" : {
            "action" : {
              "keystroke" : {
                "key" : "esc"
              }
            },
            "createdAt" : "2026-01-01T00:00:00Z",
            "input" : "caps",
            "isEnabled" : true,
            "targetLayer" : "base"
          },
          "status" : "created"
        }
        """)
    }

    // MARK: - RuleAddResult (replaced)

    func testRuleAddReplacedSnapshot() throws {
        let rule = CustomRule(input: "caps", action: .keystroke(key: "lctl"), createdAt: fixedDate)
        let detail = CLIRuleDetail(from: rule)
        let value = RuleAddResult.replaced(detail)
        let json = try encode(value)
        let dict = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        XCTAssertEqual(dict["status"] as? String, "replaced")
        XCTAssertNotNil(dict["rule"])
    }

    // MARK: - RuleAddResult (merged)

    func testRuleAddMergedSnapshot() throws {
        let rule = CustomRule(
            input: "a",
            action: .keystroke(key: "a"),
            createdAt: fixedDate,
            behavior: .dualRole(DualRoleBehavior(
                tapAction: .keystroke(key: "a"),
                holdAction: .keystroke(key: "lctl")
            ))
        )
        let detail = CLIRuleDetail(from: rule)
        let value = RuleAddResult.merged(detail)
        let json = try encode(value)
        let dict = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        XCTAssertEqual(dict["status"] as? String, "merged")
        let ruleDict = dict["rule"] as! [String: Any]
        XCTAssertEqual(ruleDict["input"] as? String, "a")
        XCTAssertNotNil(ruleDict["behavior"])
    }

    // MARK: - RuleAddResult (skipped)

    func testRuleAddSkippedSnapshot() throws {
        let value = RuleAddResult.skipped
        try assertSnapshot(value, expected: """
        {
          "status" : "skipped"
        }
        """)
    }

    // MARK: - CLIError

    func testErrorSnapshot() throws {
        let value = CLIError.conflict(
            "Rule already exists for 'caps'",
            hint: "Use --on-conflict=replace"
        )
        try assertSnapshot(value, expected: """
        {
          "code" : 4,
          "hint" : "Use --on-conflict=replace",
          "message" : "Rule already exists for 'caps'"
        }
        """)
    }

    func testErrorWithDetailsSnapshot() throws {
        let value = CLIError.validation(
            "Invalid JSON",
            hint: "Check syntax",
            details: ["Expected '{' at position 0"]
        )
        try assertSnapshot(value, expected: """
        {
          "code" : 3,
          "details" : [
            "Expected '{' at position 0"
          ],
          "hint" : "Check syntax",
          "message" : "Invalid JSON"
        }
        """)
    }

    // MARK: - CLIExportedCollection (round-trip via JSON)

    func testExportedCollectionSnapshotKeys() throws {
        let json = """
        {"name":"Test","summary":"desc","category":"custom","isEnabled":true,"targetLayer":"base","mappings":[{"input":"caps","action":{"keystroke":{"key":"esc"}}}]}
        """
        let value = try decoder.decode(CLIExportedCollection.self, from: Data(json.utf8))
        let reencoded = try encode(value)
        let dict = try JSONSerialization.jsonObject(with: Data(reencoded.utf8)) as! [String: Any]
        XCTAssertEqual(Set(dict.keys), ["category", "isEnabled", "mappings", "name", "summary", "targetLayer"])
        let mappings = dict["mappings"] as! [[String: Any]]
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(Set(mappings[0].keys), ["action", "input"])
    }

    // MARK: - CLIStatusResult

    func testStatusResultSnapshotKeys() throws {
        let value = CLIStatusResult(
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
            activeRuntimePathTitle: "LaunchDaemon",
            activeRuntimePathDetail: "Running",
            hasConflicts: false,
            timestamp: fixedDate
        )
        let json = try encode(value)
        let dict = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let expectedKeys: Set = [
            "isOperational", "helperInstalled", "helperWorking", "helperVersion",
            "keyPathAccessibility", "keyPathInputMonitoring",
            "kanataAccessibility", "kanataInputMonitoring",
            "kanataBinaryInstalled", "karabinerDriverInstalled", "vhidDeviceHealthy",
            "kanataRunning", "karabinerDaemonRunning", "vhidHealthy",
            "activeRuntimePathTitle", "activeRuntimePathDetail",
            "hasConflicts", "timestamp",
        ]
        XCTAssertEqual(Set(dict.keys), expectedKeys, "Status result key set changed — this breaks agent contracts")
    }

    // MARK: - CLIInstallerReport

    func testInstallerReportSnapshot() throws {
        let json = """
        {"success":true,"steps":[{"name":"install-helper","success":true}],"fastRepair":false}
        """
        let value = try decoder.decode(CLIInstallerReport.self, from: Data(json.utf8))
        try assertSnapshot(value, expected: """
        {
          "fastRepair" : false,
          "steps" : [
            {
              "name" : "install-helper",
              "success" : true
            }
          ],
          "success" : true
        }
        """)
    }

    // MARK: - CLIRuleDetail (full)

    func testRuleDetailFullSnapshot() throws {
        let rule = CustomRule(
            title: "Caps to Escape",
            input: "caps",
            action: .keystroke(key: "esc"),
            shiftedOutput: "caps",
            notes: "Standard remap",
            createdAt: fixedDate
        )
        let detail = CLIRuleDetail(from: rule)
        let json = try encode(detail)
        let dict = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let expectedKeys: Set = [
            "input", "action", "shiftedOutput", "title", "notes",
            "targetLayer", "isEnabled", "createdAt",
        ]
        XCTAssertTrue(
            expectedKeys.isSubset(of: Set(dict.keys)),
            "Missing keys: \(expectedKeys.subtracting(Set(dict.keys)))"
        )
        XCTAssertEqual(dict["input"] as? String, "caps")
        XCTAssertEqual(dict["title"] as? String, "Caps to Escape")
    }

    // MARK: - CLIPack

    func testPackSnapshot() throws {
        let value = CLIPack(
            id: "com.keypath.pack.vim-navigation",
            name: "Vim Navigation",
            version: "1.0.0",
            category: "Navigation",
            tagline: "Hold Space for hjkl arrows",
            isInstalled: true,
            installedAt: fixedDate
        )
        try assertSnapshot(value, expected: """
        {
          "category" : "Navigation",
          "id" : "com.keypath.pack.vim-navigation",
          "installedAt" : "2026-01-01T00:00:00Z",
          "isInstalled" : true,
          "name" : "Vim Navigation",
          "tagline" : "Hold Space for hjkl arrows",
          "version" : "1.0.0"
        }
        """)
    }

    func testPackInstallResultSnapshot() throws {
        let value = CLIPackInstallResult(
            packID: "com.keypath.pack.home-row-mods",
            packName: "Home Row Mods",
            action: "installed",
            warnings: ["Enhanced by 'Vim Navigation' — install it for best results"],
            quickSettingValues: ["holdTimeout": 200]
        )
        try assertSnapshot(value, expected: """
        {
          "action" : "installed",
          "packID" : "com.keypath.pack.home-row-mods",
          "packName" : "Home Row Mods",
          "quickSettingValues" : {
            "holdTimeout" : 200
          },
          "warnings" : [
            "Enhanced by 'Vim Navigation' — install it for best results"
          ]
        }
        """)
    }

    func testPackBindingSnapshot() throws {
        let value = CLIPackBinding(
            input: "a",
            output: "a",
            holdOutput: "lctl"
        )
        try assertSnapshot(value, expected: """
        {
          "holdOutput" : "lctl",
          "input" : "a",
          "output" : "a"
        }
        """)
    }

    func testPackQuickSettingSnapshot() throws {
        let value = CLIPackQuickSetting(
            from: PackQuickSetting(
                id: "holdTimeout",
                label: "Hold timing",
                kind: .slider(defaultValue: 180, min: 120, max: 300, step: 20, unitSuffix: " ms")
            )
        )
        try assertSnapshot(value, expected: """
        {
          "defaultValue" : 180,
          "id" : "holdTimeout",
          "label" : "Hold timing",
          "max" : 300,
          "min" : 120,
          "step" : 20,
          "unitSuffix" : " ms"
        }
        """)
    }

    func testPackDepSnapshot() throws {
        let value = CLIPackDep(
            from: PackDependency(
                packID: "com.keypath.pack.vim-navigation",
                kind: .requires,
                description: "Requires Vim Navigation for arrow keys"
            )
        )
        try assertSnapshot(value, expected: """
        {
          "description" : "Requires Vim Navigation for arrow keys",
          "kind" : "requires",
          "packID" : "com.keypath.pack.vim-navigation"
        }
        """)
    }

    // MARK: - Helpers

    private func encode(_ value: some Encodable) throws -> String {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8)!
    }

    private func assertSnapshot(
        _ value: some Encodable,
        expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let actual = try encode(value)
        XCTAssertEqual(
            actual.trimmingCharacters(in: .whitespacesAndNewlines),
            expected.trimmingCharacters(in: .whitespacesAndNewlines),
            "Snapshot mismatch — output shape changed. Update the snapshot if this is intentional.",
            file: file,
            line: line
        )
    }
}
