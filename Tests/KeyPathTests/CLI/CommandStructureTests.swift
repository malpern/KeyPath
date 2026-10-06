import ArgumentParser
@testable import KeyPathCLI
import XCTest

final class CommandStructureTests: XCTestCase {
    func testCommandNameIsKeypath() {
        XCTAssertEqual(KeyPathCLI.configuration.commandName, "keypath")
    }

    func testRootHasExpectedSubcommands() {
        let names = subcommandNames(of: KeyPathCLI.self)
        for expected in ["rule", "collection", "layer", "pack", "service", "config", "system", "export", "import", "help-topics", "completions"] {
            XCTAssertTrue(names.contains(expected), "Missing subcommand: \(expected). Found: \(names)")
        }
    }

    func testRootHasPorcelainShortcuts() {
        let names = subcommandNames(of: KeyPathCLI.self)
        XCTAssertTrue(names.contains("remap"), "Missing porcelain shortcut: remap")
        XCTAssertTrue(names.contains("logs"), "Missing porcelain shortcut: logs")
        XCTAssertTrue(names.contains("unmap"), "Missing porcelain shortcut: unmap")
    }

    func testRuleHasExpectedVerbs() {
        let names = subcommandNames(of: Rule.self)
        XCTAssertEqual(Set(names), ["list", "add", "remove", "show", "enable", "disable", "ensure"])
    }

    func testCollectionHasExpectedVerbs() {
        let names = subcommandNames(of: Collection.self)
        XCTAssertEqual(Set(names), ["list", "create", "enable", "disable", "show", "rename", "delete", "duplicate", "reorder"])
    }

    func testLayerHasExpectedVerbs() {
        let names = subcommandNames(of: Layer.self)
        XCTAssertEqual(Set(names), ["list", "current", "create", "delete", "rename", "switch"])
    }

    func testPackHasExpectedVerbs() {
        let names = subcommandNames(of: Pack.self)
        XCTAssertEqual(Set(names), ["list", "show", "install", "uninstall", "configure"])
    }

    func testServiceHasExpectedVerbs() {
        let names = subcommandNames(of: Service.self)
        XCTAssertEqual(Set(names), ["reload", "logs"])
    }

    func testConfigHasExpectedVerbs() {
        let names = subcommandNames(of: Config.self)
        XCTAssertEqual(Set(names), ["show", "path", "check", "apply", "backup", "restore"])
    }

    func testSystemHasExpectedVerbs() {
        let names = subcommandNames(of: System.self)
        XCTAssertEqual(Set(names), ["inspect"])
    }

    func testUnsupportedDriverlessCommandsRejectBeforeExecution() {
        let commands = [
            ["service", "status"], ["service", "start"], ["service", "stop"], ["service", "restart"],
            ["status"], ["start"], ["stop"], ["restart"],
            ["system", "install"], ["system", "repair"], ["system", "uninstall"],
        ]
        for arguments in commands {
            for flags in [[], ["--json"], ["--dry-run"]] {
                XCTAssertThrowsError(try KeyPathCLI.parseAsRoot(arguments + flags), arguments.joined(separator: " ")) { error in
                    XCTAssertNotEqual(KeyPathCLI.exitCode(for: error), .success)
                }
            }
        }
    }

    func testSupportedConfigSimulatorAndDiagnosticsRemainRegistered() throws {
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["config", "check", "--json"]) is ConfigCheck)
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["simulate", "a", "--dry-run"]) is Simulate)
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["service", "reload"]) is ServiceReload)
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["service", "logs"]) is ServiceLogs)
        XCTAssertTrue(try KeyPathCLI.parseAsRoot(["system", "inspect"]) is SystemInspect)
        XCTAssertTrue(KeyPathCLI.helpMessage().contains("Open KeyPath.app"))
    }

    func testCompletionsOmitUnavailableCommandsAndKeepReload() {
        let completions = KeyPathCLI.completionScript(for: .zsh)
        for command in ["service_status", "service_start", "service_stop", "service_restart",
                        "system_install", "system_repair", "system_uninstall"]
        {
            XCTAssertFalse(completions.contains("_keypath_\(command)"))
        }
        XCTAssertTrue(completions.contains("_keypath_service_reload"))
        XCTAssertTrue(completions.contains("_keypath_config_check"))
    }

    func testHelpTopicsHasExpectedVerbs() {
        let names = subcommandNames(of: Help.self)
        XCTAssertEqual(Set(names), ["schemas", "examples"])
    }

    func testCompletionsHasShells() {
        let names = subcommandNames(of: Completions.self)
        XCTAssertEqual(Set(names), ["zsh", "bash", "fish", "install", "install-man", "values"])
    }

    // MARK: - Helpers

    private func subcommandNames<T: ParsableCommand>(of _: T.Type) -> [String] {
        T.configuration.subcommands.map {
            $0.configuration.commandName ?? String(describing: $0).lowercased()
        }
    }
}
