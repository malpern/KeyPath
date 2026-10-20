import ArgumentParser
import Darwin
@testable import KeyPathCLIHelp
import XCTest

final class HelpOutputContractTests: XCTestCase {
    func testServiceAndSystemExamplesDoNotAdvertiseUnavailableCommands() async throws {
        let unavailable = ["service status", "service start", "service stop", "service restart",
                           "system install", "system repair", "system uninstall"]
        for noun in ["service", "system"] {
            let jsonOutput = await captureStandardOutput {
                var parsed = try! HelpExamples.parse([noun, "--json"])
                try! await parsed.run()
            }
            let data = try XCTUnwrap(jsonOutput.data(using: .utf8))
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
            for command in unavailable {
                XCTAssertFalse(jsonOutput.contains(command), "Examples must not advertise \(command)")
            }
            if noun == "service" {
                XCTAssertTrue(jsonOutput.contains("service reload"))
                XCTAssertTrue(jsonOutput.contains("service logs"))
                XCTAssertTrue(jsonOutput.contains("open -a KeyPath"))
            } else {
                XCTAssertTrue(jsonOutput.contains("system inspect"))
                XCTAssertTrue(jsonOutput.contains("not live app-session health"))
            }
        }
    }

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

    private func assertUnknownHelpOutput(
        command: (some AsyncParsableCommand).Type,
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

    private func captureStandardOutput(_ operation: () async -> Void) async -> String {
        let pipe = Pipe()
        let original = dup(STDOUT_FILENO)
        XCTAssertNotEqual(original, -1)
        XCTAssertNotEqual(dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO), -1)
        await operation()
        fflush(stdout)
        XCTAssertNotEqual(dup2(original, STDOUT_FILENO), -1)
        close(original)
        pipe.fileHandleForWriting.closeFile()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
