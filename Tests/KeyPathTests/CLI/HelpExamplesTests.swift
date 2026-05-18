import ArgumentParser
@testable import KeyPathCLI
import XCTest

final class HelpExamplesTests: XCTestCase {
    func testExamplesCommandIsRegistered() {
        let names = Help.configuration.subcommands.map {
            $0.configuration.commandName ?? String(describing: $0).lowercased()
        }
        XCTAssertTrue(names.contains("examples"))
    }

    func testExamplesCommandParsesWithoutNoun() throws {
        _ = try HelpExamples.parse([])
    }

    func testExamplesCommandParsesWithNoun() throws {
        let cmd = try HelpExamples.parse(["rule"])
        XCTAssertEqual(cmd.noun, "rule")
    }

    func testExamplesCommandParsesWithJSONFlag() throws {
        let cmd = try HelpExamples.parse(["rule", "--json"])
        XCTAssertEqual(cmd.noun, "rule")
        XCTAssertTrue(cmd.globals.json)
    }

    func testAllExpectedNounsHaveExamples() throws {
        let expectedNouns = ["rule", "collection", "layer", "service", "config", "system"]
        for noun in expectedNouns {
            let cmd = try HelpExamples.parse([noun])
            XCTAssertEqual(cmd.noun, noun)
        }
    }
}
