import ArgumentParser
@testable import KeyPathCLI
import XCTest

final class CLIHelpSchemasTests: XCTestCase {
    // MARK: - Schema nouns are recognized

    func testHelpSchemasAcceptsActionNoun() throws {
        let cmd = try HelpSchemas.parse(["action"])
        XCTAssertEqual(cmd.noun, "action")
    }

    func testHelpSchemasAcceptsBehaviorNoun() throws {
        let cmd = try HelpSchemas.parse(["behavior"])
        XCTAssertEqual(cmd.noun, "behavior")
    }

    func testHelpSchemasAcceptsRuleNoun() throws {
        let cmd = try HelpSchemas.parse(["rule"])
        XCTAssertEqual(cmd.noun, "rule")
    }

    func testHelpSchemasAcceptsCollectionNoun() throws {
        let cmd = try HelpSchemas.parse(["collection"])
        XCTAssertEqual(cmd.noun, "collection")
    }

    func testHelpSchemasNoNounListsAll() throws {
        let cmd = try HelpSchemas.parse([])
        XCTAssertNil(cmd.noun)
    }

    // MARK: - CommandStructure includes new schemas

    func testHelpTopicsHasSchemasSubcommand() {
        let names = Help.configuration.subcommands.map {
            $0.configuration.commandName ?? ""
        }
        XCTAssertTrue(names.contains("schemas"))
    }
}
