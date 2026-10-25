import Foundation
import Security
@preconcurrency import XCTest

final class HelperTrustContractTests: XCTestCase {
    func testBundledCLIHasStableIdentityAfterHelperRemoval() throws {
        let root = repositoryRoot()
        let cliIdentifier = "com.keypath.KeyPath.CLI"

        let buildAndSign = try contents(
            of: root.appendingPathComponent("Scripts/build-and-sign.sh")
        )
        let releaseContract = try contents(
            of: root.appendingPathComponent("Scripts/verify-release-signing-contract.sh")
        )
        let quickDeploy = try contents(
            of: root.appendingPathComponent("Scripts/quick-deploy.sh")
        )
        let verifyInstalledApp = try contents(
            of: root.appendingPathComponent("Scripts/verify-installed-app.sh")
        )

        XCTAssertTrue(
            buildAndSign.contains(#"--identifier "\#(cliIdentifier)""#),
            "Release signing must stamp keypath-cli with its stable identifier."
        )
        XCTAssertTrue(
            quickDeploy.contains(#"--identifier "\#(cliIdentifier)""#),
            "Quick deploy signing must preserve the helper-trusted CLI identifier."
        )
        XCTAssertTrue(
            verifyInstalledApp.contains(#"Identifier=com\.keypath\.KeyPath\.CLI"#),
            "Installed-app verification must fail if keypath-cli is signed with the wrong identifier."
        )
        XCTAssertTrue(releaseContract.contains("CLI signing uses a stable identifier"))
        XCTAssertFalse(buildAndSign.contains("KeyPathHelper"))
    }

    func testReleaseSigningContractDoesNotBuildPrivilegedHelper() throws {
        let root = repositoryRoot()
        let releaseContract = try contents(
            of: root.appendingPathComponent("Scripts/verify-release-signing-contract.sh")
        )
        XCTAssertTrue(releaseContract.contains("release build does not build the privileged helper"))
        XCTAssertTrue(releaseContract.contains("release build omits privileged helper and LaunchDaemon packaging"))
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
