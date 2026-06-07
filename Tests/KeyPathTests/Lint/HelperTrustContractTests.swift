import Foundation
import Security
@preconcurrency import XCTest

final class HelperTrustContractTests: XCTestCase {
    func testBundledCLIIdentifierMatchesHelperTrustRequirement() throws {
        let root = repositoryRoot()
        let cliIdentifier = "com.keypath.KeyPath.CLI"

        let helperMain = try contents(
            of: root.appendingPathComponent("Sources/KeyPathHelper/main.swift")
        )
        let buildAndSign = try contents(
            of: root.appendingPathComponent("Scripts/build-and-sign.sh")
        )
        let quickDeploy = try contents(
            of: root.appendingPathComponent("Scripts/quick-deploy.sh")
        )
        let verifyInstalledApp = try contents(
            of: root.appendingPathComponent("Scripts/verify-installed-app.sh")
        )

        XCTAssertTrue(
            helperMain.contains(#"identifier \"\#(cliIdentifier)\""#),
            "The helper release trust requirement must accept the app-bundled CLI identifier."
        )
        XCTAssertTrue(
            buildAndSign.contains(#"--identifier "\#(cliIdentifier)""#),
            "Release signing must stamp keypath-cli with the helper-trusted identifier."
        )
        XCTAssertTrue(
            quickDeploy.contains(#"--identifier "\#(cliIdentifier)""#),
            "Quick deploy signing must preserve the helper-trusted CLI identifier."
        )
        XCTAssertTrue(
            verifyInstalledApp.contains(#"Identifier=com\.keypath\.KeyPath\.CLI"#),
            "Installed-app verification must fail if keypath-cli is signed with the wrong identifier."
        )
    }

    func testHelperReleaseTrustRequirementParses() {
        let releaseRequirement =
            #"(identifier "com.keypath.KeyPath" or identifier "com.keypath.KeyPath.CLI") and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = X2RKZ5TG99"#

        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(releaseRequirement as CFString, [], &requirement)

        XCTAssertEqual(status, errSecSuccess)
        XCTAssertNotNil(requirement)
    }
}

// MARK: - Helpers

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: file.description)
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}

private func contents(of url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
}
