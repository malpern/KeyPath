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
        XCTAssertTrue(names.contains("status"), "Missing porcelain shortcut: status")
        XCTAssertTrue(names.contains("remap"), "Missing porcelain shortcut: remap")
        XCTAssertTrue(names.contains("start"), "Missing porcelain shortcut: start")
        XCTAssertTrue(names.contains("stop"), "Missing porcelain shortcut: stop")
        XCTAssertTrue(names.contains("restart"), "Missing porcelain shortcut: restart")
        XCTAssertTrue(names.contains("logs"), "Missing porcelain shortcut: logs")
        XCTAssertTrue(names.contains("unmap"), "Missing porcelain shortcut: unmap")
    }

    func testRuleHasExpectedVerbs() {
        let names = subcommandNames(of: Rule.self)
        XCTAssertEqual(Set(names), ["list", "add", "remove", "show"])
    }

    func testCollectionHasExpectedVerbs() {
        let names = subcommandNames(of: Collection.self)
        XCTAssertEqual(Set(names), ["list", "create", "enable", "disable", "show", "rename", "delete", "duplicate", "reorder"])
    }

    func testLayerHasExpectedVerbs() {
        let names = subcommandNames(of: Layer.self)
        XCTAssertEqual(Set(names), ["list", "create", "delete", "rename", "switch"])
    }

    func testPackHasExpectedVerbs() {
        let names = subcommandNames(of: Pack.self)
        XCTAssertEqual(Set(names), ["list", "show", "install", "uninstall", "configure"])
    }

    func testServiceHasExpectedVerbs() {
        let names = subcommandNames(of: Service.self)
        XCTAssertEqual(Set(names), ["status", "start", "stop", "restart", "reload", "logs"])
    }

    func testConfigHasExpectedVerbs() {
        let names = subcommandNames(of: Config.self)
        XCTAssertEqual(Set(names), ["show", "path", "check", "apply"])
    }

    func testSystemHasExpectedVerbs() {
        let names = subcommandNames(of: System.self)
        XCTAssertEqual(Set(names), ["install", "repair", "uninstall", "inspect"])
    }

    func testHelpTopicsHasExpectedVerbs() {
        let names = subcommandNames(of: Help.self)
        XCTAssertEqual(Set(names), ["schemas", "examples"])
    }

    func testCompletionsHasShells() {
        let names = subcommandNames(of: Completions.self)
        XCTAssertEqual(Set(names), ["zsh", "bash", "fish", "install", "install-man"])
    }

    // MARK: - Helpers

    private func subcommandNames<T: ParsableCommand>(of _: T.Type) -> [String] {
        T.configuration.subcommands.map {
            $0.configuration.commandName ?? String(describing: $0).lowercased()
        }
    }
}
