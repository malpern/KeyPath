import ArgumentParser
@testable import KeyPathCLI
import XCTest

final class CLICommandValidationTests: XCTestCase {
    // MARK: - RuleAdd validation

    func testRuleAddRejectsConflictingOutputModes() {
        // --action and <output> together should fail
        XCTAssertThrowsError(
            try RuleAdd.parse(["caps", "esc", "--action", #"{"hyper":{}}"#])
        )
    }

    func testRuleAddRejectsTapWithoutHold() {
        XCTAssertThrowsError(
            try RuleAdd.parse(["caps", "--tap", "a"])
        )
    }

    func testRuleAddRejectsHoldWithoutTap() {
        XCTAssertThrowsError(
            try RuleAdd.parse(["caps", "--hold", "lctl"])
        )
    }

    func testRuleAddRejectsNoOutputMode() {
        // No output, no --action, no --tap/--hold, no --behavior → should fail
        XCTAssertThrowsError(
            try RuleAdd.parse(["caps"])
        )
    }

    func testRuleAddRejectsTapHoldWithAction() {
        XCTAssertThrowsError(
            try RuleAdd.parse(["caps", "--tap", "a", "--hold", "lctl", "--action", #"{"hyper":{}}"#])
        )
    }

    func testRuleAddAcceptsSimpleRemap() throws {
        let cmd = try RuleAdd.parse(["caps", "esc"])
        XCTAssertEqual(cmd.input, "caps")
        XCTAssertEqual(cmd.output, "esc")
        XCTAssertNil(cmd.action)
        XCTAssertNil(cmd.tap)
        XCTAssertNil(cmd.hold)
    }

    func testRuleAddAcceptsActionJSON() throws {
        let cmd = try RuleAdd.parse(["caps", "--action", #"{"hyper":{}}"#])
        XCTAssertEqual(cmd.input, "caps")
        XCTAssertNil(cmd.output)
        XCTAssertEqual(cmd.action, #"{"hyper":{}}"#)
    }

    func testRuleAddAcceptsTapHold() throws {
        let cmd = try RuleAdd.parse(["a", "--tap", "a", "--hold", "lctl", "--tap-timeout", "250"])
        XCTAssertEqual(cmd.input, "a")
        XCTAssertEqual(cmd.tap, "a")
        XCTAssertEqual(cmd.hold, "lctl")
        XCTAssertEqual(cmd.tapTimeout, 250)
    }

    func testRuleAddAcceptsBehaviorOnly() throws {
        let json = #"{"dualRole":{"tapAction":{"keystroke":{"key":"a"}},"holdAction":{"keystroke":{"key":"lctl"}},"tapTimeout":200,"holdTimeout":200}}"#
        let cmd = try RuleAdd.parse(["a", "--behavior", json])
        XCTAssertEqual(cmd.input, "a")
        XCTAssertEqual(cmd.behavior, json)
    }

    func testRuleAddAcceptsAllOptionalFlags() throws {
        let cmd = try RuleAdd.parse([
            "caps", "esc",
            "--shifted", "~",
            "--layer", "nav",
            "--title", "Escape Key",
            "--notes", "Remap caps to esc",
            "--dry-run",
            "--on-conflict", "replace",
            "--apply",
        ])
        XCTAssertEqual(cmd.shifted, "~")
        XCTAssertEqual(cmd.layer, "nav")
        XCTAssertEqual(cmd.title, "Escape Key")
        XCTAssertEqual(cmd.notes, "Remap caps to esc")
        XCTAssertTrue(cmd.globals.dryRun)
        XCTAssertEqual(cmd.globals.onConflict, .replace)
        XCTAssertTrue(cmd.apply)
    }

    // MARK: - RuleList validation

    func testRuleListAcceptsEnabledOnly() throws {
        let cmd = try RuleList.parse(["--enabled-only"])
        XCTAssertTrue(cmd.enabledOnly)
    }

    func testRuleListDefaultsToAllRules() throws {
        let cmd = try RuleList.parse([])
        XCTAssertFalse(cmd.enabledOnly)
    }

    // MARK: - Collection command parsing

    func testCollectionCreateParsesArguments() throws {
        let cmd = try CollectionCreate.parse(["My Rules", "--category", "productivity", "--summary", "A test"])
        XCTAssertEqual(cmd.name, "My Rules")
        XCTAssertEqual(cmd.category, "productivity")
        XCTAssertEqual(cmd.summary, "A test")
    }

    func testCollectionRenameParsesArguments() throws {
        let cmd = try CollectionRename.parse(["Old Name", "New Name"])
        XCTAssertEqual(cmd.nameOrId, "Old Name")
        XCTAssertEqual(cmd.newName, "New Name")
    }

    func testCollectionDeleteParsesArguments() throws {
        let cmd = try CollectionDelete.parse(["Doomed", "--force"])
        XCTAssertEqual(cmd.nameOrId, "Doomed")
        XCTAssertTrue(cmd.force)
    }

    func testCollectionDuplicateParsesArguments() throws {
        let cmd = try CollectionDuplicate.parse(["Original", "--name", "Clone"])
        XCTAssertEqual(cmd.nameOrId, "Original")
        XCTAssertEqual(cmd.name, "Clone")
    }

    func testCollectionReorderParsesArguments() throws {
        let cmd = try CollectionReorder.parse(["Vim Layer", "--position", "0"])
        XCTAssertEqual(cmd.nameOrId, "Vim Layer")
        XCTAssertEqual(cmd.position, 0)
    }

    // MARK: - Service command parsing

    func testServiceLogsParsesLineCount() throws {
        let cmd = try ServiceLogs.parse(["--lines", "100"])
        XCTAssertEqual(cmd.lines, 100)
    }

    func testServiceLogsDefaultsTo50() throws {
        let cmd = try ServiceLogs.parse([])
        XCTAssertEqual(cmd.lines, 50)
    }

    // MARK: - Simulate command parsing

    func testSimulateAcceptsRawTimeline() throws {
        let cmd = try Simulate.parse(["--raw", "d:f t:100 d:j t:50 u:j t:50 u:f"])
        XCTAssertEqual(cmd.rawSimulation, "d:f t:100 d:j t:50 u:j t:50 u:f")
        XCTAssertTrue(cmd.keys.isEmpty)
    }

    func testSimulateAcceptsSimFile() throws {
        let cmd = try Simulate.parse(["--sim-file", "/tmp/keypath-sim.txt"])
        XCTAssertEqual(cmd.simulationFile, "/tmp/keypath-sim.txt")
        XCTAssertTrue(cmd.keys.isEmpty)
    }

    func testSimulateRejectsRawAndKeysTogether() {
        XCTAssertThrowsError(
            try Simulate.parse(["--raw", "d:f t:100 u:f", "f"])
        )
    }

    func testSimulateRejectsRawAndSimFileTogether() {
        XCTAssertThrowsError(
            try Simulate.parse(["--raw", "d:f t:100 u:f", "--sim-file", "/tmp/keypath-sim.txt"])
        )
    }

    func testSimulateRejectsNoInput() {
        XCTAssertThrowsError(
            try Simulate.parse([])
        )
    }

    func testSimulateRawDryRunPreviewCountsPressReleaseEvents() {
        let raw = "d:f t:100 d:j t:50 u:j t:50 u:f"
        let keyCount = Simulate.rawEventCount(in: raw)
        let message = Simulate.dryRunDescription(rawContent: raw, keyCount: keyCount, simContent: raw)

        XCTAssertEqual(keyCount, 4)
        XCTAssertEqual(message, "Would simulate raw timeline (4 event(s)): d:f t:100 d:j t:50 u:j t:50 u:f")
    }

    func testSimulateNormalizesRawTimelineWhitespace() {
        XCTAssertEqual(
            Simulate.normalizedRawSimulationContent("d:f t:100 u:f\n"),
            "d:f t:100 u:f"
        )
    }

    // MARK: - System command parsing

    func testSystemRepairAcceptsOpenPermissions() throws {
        let cmd = try SystemRepair.parse(["--dry-run", "--open-permissions"])
        XCTAssertTrue(cmd.globals.dryRun)
        XCTAssertTrue(cmd.openPermissions)
    }

    // MARK: - Global options

    func testGlobalOptionsDryRun() throws {
        let cmd = try RuleAdd.parse(["caps", "esc", "--dry-run"])
        XCTAssertTrue(cmd.globals.dryRun)
    }

    func testGlobalOptionsOnConflictReplace() throws {
        let cmd = try RuleAdd.parse(["caps", "esc", "--on-conflict", "replace"])
        XCTAssertEqual(cmd.globals.onConflict, .replace)
    }

    func testGlobalOptionsOnConflictSkip() throws {
        let cmd = try RuleAdd.parse(["caps", "esc", "--on-conflict", "skip"])
        XCTAssertEqual(cmd.globals.onConflict, .skip)
    }

    func testGlobalOptionsJSON() throws {
        let cmd = try RuleAdd.parse(["caps", "esc", "--json"])
        XCTAssertTrue(cmd.globals.json)
    }
}
