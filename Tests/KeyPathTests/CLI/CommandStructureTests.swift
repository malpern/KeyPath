import ArgumentParser
@testable import KeyPathCLI
import XCTest

final class CommandStructureTests: XCTestCase {
    func testCommandNameIsKeypath() {
        XCTAssertEqual(KeyPathCLI.configuration.commandName, "keypath")
    }

    func testRootHasExpectedSubcommands() {
        let names = subcommandNames(of: KeyPathCLI.self)
        for expected in ["rule", "collection", "layer", "service", "config", "system", "help-topics", "completions"] {
            XCTAssertTrue(names.contains(expected), "Missing subcommand: \(expected). Found: \(names)")
        }
    }

    func testRootHasPorcelainShortcuts() {
        let names = subcommandNames(of: KeyPathCLI.self)
        XCTAssertTrue(names.contains("status"), "Missing porcelain shortcut: status")
        XCTAssertTrue(names.contains("remap"), "Missing porcelain shortcut: remap")
    }

    func testRuleHasExpectedVerbs() {
        let names = subcommandNames(of: Rule.self)
        XCTAssertEqual(Set(names), ["list", "add", "remove", "show"])
    }

    func testCollectionHasExpectedVerbs() {
        let names = subcommandNames(of: Collection.self)
        XCTAssertEqual(Set(names), ["list", "enable", "disable", "show"])
    }

    func testLayerHasExpectedVerbs() {
        let names = subcommandNames(of: Layer.self)
        XCTAssertEqual(Set(names), ["list", "switch"])
    }

    func testServiceHasExpectedVerbs() {
        let names = subcommandNames(of: Service.self)
        XCTAssertEqual(Set(names), ["status", "reload"])
    }

    func testConfigHasExpectedVerbs() {
        let names = subcommandNames(of: Config.self)
        XCTAssertEqual(Set(names), ["show", "path", "check", "apply"])
    }

    func testSystemHasExpectedVerbs() {
        let names = subcommandNames(of: System.self)
        XCTAssertEqual(Set(names), ["install", "repair", "uninstall", "inspect"])
    }

    func testHelpTopicsHasSchemas() {
        let names = subcommandNames(of: Help.self)
        XCTAssertTrue(names.contains("schemas"))
    }

    func testCompletionsHasShells() {
        let names = subcommandNames(of: Completions.self)
        XCTAssertEqual(Set(names), ["zsh", "bash", "fish"])
    }

    // MARK: - Helpers

    private func subcommandNames<T: ParsableCommand>(of _: T.Type) -> [String] {
        T.configuration.subcommands.map {
            $0.configuration.commandName ?? String(describing: $0).lowercased()
        }
    }
}
