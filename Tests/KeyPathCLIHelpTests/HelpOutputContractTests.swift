import ArgumentParser
import Darwin
@testable import KeyPathCLIHelp
import XCTest

final class HelpOutputContractTests: XCTestCase {
    func testUnknownSchemaPreservesJSONAndHumanErrorContracts() async throws {
        try await assertUnknownHelpOutput(
            command: HelpSchemas.self,
            noun: "not-a-schema",
            entity: "Schema",
            listCommand: "keypath help-topics schemas"
        )
    }

    func testUnknownExamplePreservesJSONAndHumanErrorContracts() async throws {
        try await assertUnknownHelpOutput(
            command: HelpExamples.self,
            noun: "not-an-example",
            entity: "Examples",
            listCommand: "keypath help-topics examples"
        )
    }

    private func assertUnknownHelpOutput<Command: AsyncParsableCommand>(
        command: Command.Type,
        noun: String,
        entity: String,
        listCommand: String
    ) async throws {
        let jsonError = await captureStandardError {
            var parsed = try! command.parse([noun, "--json"])
            _ = try? await parsed.run()
        }
        let jsonData = try XCTUnwrap(jsonError.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        XCTAssertEqual(json?["apiVersion"] as? Int, 1)
        let error = try XCTUnwrap(json?["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, 5)
        XCTAssertEqual(error["message"] as? String, "\(entity) not found: '\(noun)'")
        XCTAssertEqual(error["hint"] as? String, "Run '\(listCommand)' to see available \(entity.lowercased())s")
        XCTAssertEqual(error["details"] as? [String], ["query: '\(noun)'"])

        let humanError = await captureStandardError {
            var parsed = try! command.parse([noun, "--no-json"])
            _ = try? await parsed.run()
        }
        XCTAssertTrue(humanError.contains("Error: \(entity) not found: '\(noun)'"))
        XCTAssertTrue(humanError.contains("Hint: Run '\(listCommand)' to see available \(entity.lowercased())s"))
        XCTAssertTrue(humanError.contains("  query: '\(noun)'"))
    }

    private func captureStandardError(_ operation: () async -> Void) async -> String {
        let pipe = Pipe()
        let original = dup(STDERR_FILENO)
        XCTAssertNotEqual(original, -1)
        XCTAssertNotEqual(dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO), -1)

        await operation()
        fflush(stderr)
        XCTAssertNotEqual(dup2(original, STDERR_FILENO), -1)
        close(original)
        pipe.fileHandleForWriting.closeFile()

        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
