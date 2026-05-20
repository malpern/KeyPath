import ArgumentParser
@testable import KeyPathCLI
import XCTest

final class CLISmokeTests: XCTestCase {
    // MARK: - Global options

    func testGlobalOptionsDefaults() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["rule", "list"]) as! RuleList
        XCTAssertFalse(cmd.globals.json)
        XCTAssertFalse(cmd.globals.noJson)
        XCTAssertFalse(cmd.globals.quiet)
        XCTAssertFalse(cmd.globals.dryRun)
        XCTAssertEqual(cmd.globals.timeout, 30)
        XCTAssertEqual(cmd.globals.onConflict, .fail)
    }

    func testGlobalOptionsJSON() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["rule", "list", "--json"]) as! RuleList
        XCTAssertTrue(cmd.globals.json)
    }

    func testGlobalOptionsQuiet() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["collection", "list", "--quiet"]) as! CollectionList
        XCTAssertTrue(cmd.globals.quiet)
    }

    func testGlobalOptionsTimeout() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["service", "status", "--timeout", "60"]) as! ServiceStatus
        XCTAssertEqual(cmd.globals.timeout, 60)
    }

    func testGlobalOptionsDryRun() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["rule", "add", "caps", "esc", "--dry-run"]) as! RuleAdd
        XCTAssertTrue(cmd.globals.dryRun)
    }

    // MARK: - Rule commands

    func testRuleAddParses() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["rule", "add", "caps", "esc"]) as! RuleAdd
        XCTAssertEqual(cmd.input, "caps")
        XCTAssertEqual(cmd.output, "esc")
    }

    func testRuleAddWithBehavior() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["rule", "add", "caps", "esc", "--behavior", "tap-hold"]) as! RuleAdd
        XCTAssertEqual(cmd.behavior, "tap-hold")
    }

    func testRuleRemoveParses() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["rule", "remove", "caps"]) as! RuleRemove
        XCTAssertEqual(cmd.input, "caps")
    }

    func testRuleShowParses() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["rule", "show", "caps"]) as! RuleShow
        XCTAssertEqual(cmd.input, "caps")
    }

    func testRuleEnableParses() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["rule", "enable", "caps"]) as! RuleEnable
        XCTAssertEqual(cmd.input, "caps")
    }

    func testRuleEnsureParses() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["rule", "ensure", "caps", "esc"]) as! RuleEnsure
        XCTAssertEqual(cmd.input, "caps")
        XCTAssertEqual(cmd.output, "esc")
    }

    // MARK: - Collection commands

    func testCollectionCreateParses() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["collection", "create", "My Collection"]) as! CollectionCreate
        XCTAssertEqual(cmd.name, "My Collection")
    }

    func testCollectionDeleteParses() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["collection", "delete", "test"]) as! CollectionDelete
        XCTAssertEqual(cmd.nameOrId, "test")
    }

    // MARK: - Pack commands

    func testPackInstallParses() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["pack", "install", "caps-escape"]) as! PackInstall
        XCTAssertEqual(cmd.nameOrId, "caps-escape")
    }

    func testPackUninstallParses() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["pack", "uninstall", "caps-escape"]) as! PackUninstall
        XCTAssertEqual(cmd.nameOrId, "caps-escape")
    }

    // MARK: - Config commands

    func testConfigCheckParses() throws {
        _ = try KeyPathCLI.parseAsRoot(["config", "check"]) as! ConfigCheck
    }

    func testConfigShowParses() throws {
        _ = try KeyPathCLI.parseAsRoot(["config", "show"]) as! ConfigShow
    }

    // MARK: - Service commands

    func testServiceLogsWithLines() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["service", "logs", "--lines", "100"]) as! ServiceLogs
        XCTAssertEqual(cmd.lines, 100)
    }

    // MARK: - System commands

    func testSystemUninstallDeleteConfig() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["system", "uninstall", "--delete-config"]) as! SystemUninstall
        XCTAssertTrue(cmd.deleteConfig)
    }

    // MARK: - Conflict strategy

    func testOnConflictReplace() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["rule", "add", "a", "b", "--on-conflict", "replace"]) as! RuleAdd
        XCTAssertEqual(cmd.globals.onConflict, .replace)
    }

    // MARK: - Invalid input

    func testUnknownSubcommandThrows() {
        XCTAssertThrowsError(try KeyPathCLI.parseAsRoot(["nonexistent"]))
    }

    func testMissingRequiredArgThrows() {
        XCTAssertThrowsError(try KeyPathCLI.parseAsRoot(["rule", "add"]))
    }

    func testInvalidOnConflictThrows() {
        XCTAssertThrowsError(try KeyPathCLI.parseAsRoot(["--on-conflict", "nope", "rule", "list"]))
    }

    // MARK: - Porcelain shortcuts

    func testStatusShortcutParses() throws {
        _ = try KeyPathCLI.parseAsRoot(["status"]) as! StatusShortcut
    }

    func testRemapShortcutParses() throws {
        let cmd = try KeyPathCLI.parseAsRoot(["remap", "caps", "esc"]) as! RemapShortcut
        XCTAssertEqual(cmd.input, "caps")
        XCTAssertEqual(cmd.output, "esc")
    }
}
