import Foundation
import XCTest

final class DeploymentScriptContractTests: XCTestCase {
    func testInstalledAppDeployScriptsUseCrossWorktreeLock() throws {
        let root = repositoryRoot()
        let lockScript = try contents(of: root.appendingPathComponent("Scripts/lib/deploy-lock.sh"))
        let quickDeploy = try contents(of: root.appendingPathComponent("Scripts/quick-deploy.sh"))
        let buildAndSign = try contents(of: root.appendingPathComponent("Scripts/build-and-sign.sh"))

        XCTAssertTrue(
            lockScript.contains("KEYPATH_DEPLOY_LOCK_DIR"),
            "The deploy lock must be shared outside any single worktree."
        )
        XCTAssertTrue(
            quickDeploy.contains(#"source "$SCRIPT_DIR/lib/deploy-lock.sh""#),
            "quick-deploy must use the shared deploy lock before mutating /Applications/KeyPath.app."
        )
        XCTAssertTrue(
            quickDeploy.contains("keypath_acquire_deploy_lock"),
            "quick-deploy must acquire the shared deploy lock."
        )
        XCTAssertTrue(
            quickDeploy.contains("keypath_release_deploy_lock"),
            "quick-deploy must release the shared deploy lock during cleanup."
        )
        XCTAssertTrue(
            buildAndSign.contains(#"source "$SCRIPT_DIR/lib/deploy-lock.sh""#),
            "build-and-sign must use the shared deploy lock during release-candidate and release deploys."
        )
        XCTAssertTrue(
            buildAndSign.contains("keypath_acquire_deploy_lock"),
            "build-and-sign must acquire the shared deploy lock."
        )
        XCTAssertTrue(
            buildAndSign.contains("trap keypath_release_deploy_lock EXIT"),
            "build-and-sign must release the shared deploy lock on exit."
        )
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
