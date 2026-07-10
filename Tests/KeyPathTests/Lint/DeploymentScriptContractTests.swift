import Foundation
import XCTest

final class DeploymentScriptContractTests: XCTestCase {
    func testCanonicalBuildScriptsUseStableXcodeContract() throws {
        let root = repositoryRoot()
        let xcodeContract = try contents(of: root.appendingPathComponent("Scripts/lib/xcode.sh"))
        let consumers = [
            "Scripts/run-tests-safe.sh",
            "Scripts/quick-deploy.sh",
            "Scripts/build-and-sign.sh",
            "Scripts/release-doctor.sh",
        ]

        XCTAssertTrue(xcodeContract.contains("Xcode-26.6.0.app/Contents/Developer"))
        XCTAssertTrue(xcodeContract.contains("KEYPATH_DEV_XCODE_DEVELOPER_DIR"))
        XCTAssertTrue(xcodeContract.contains("keypath_use_stable_xcode"))

        for relativePath in consumers {
            let script = try contents(of: root.appendingPathComponent(relativePath))
            XCTAssertTrue(
                script.contains(#"source "$SCRIPT_DIR/lib/xcode.sh""#),
                "\(relativePath) must source the stable Xcode contract."
            )
            XCTAssertTrue(
                script.contains("keypath_use_stable_xcode"),
                "\(relativePath) must select stable Xcode before invoking developer tools."
            )
        }
    }

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

    func testQuickDeployPreservesBuildFailureDiagnostics() throws {
        let root = repositoryRoot()
        let quickDeploy = try contents(of: root.appendingPathComponent("Scripts/quick-deploy.sh"))

        XCTAssertTrue(
            quickDeploy.contains(#"BUILD_LOG_DIR="$PROJECT_DIR/.build/logs/quick-deploy""#),
            "quick-deploy must write failed build logs to a stable path under .build."
        )
        XCTAssertTrue(
            quickDeploy.contains("print_build_failure_diagnostics"),
            "quick-deploy must print useful diagnostics when swift build fails."
        )
        XCTAssertTrue(
            quickDeploy.contains("Full build log preserved at:"),
            "quick-deploy failure output must tell developers where the full log is."
        )
        XCTAssertTrue(
            quickDeploy.contains("KEYPATH_QUICK_DEPLOY_LOG_RETENTION_DAYS"),
            "quick-deploy must expose a retention setting for preserved failure logs."
        )
        XCTAssertTrue(
            quickDeploy.contains("prune_old_build_logs"),
            "quick-deploy must prune old preserved build logs."
        )
        XCTAssertTrue(
            quickDeploy.contains("BIN_DIR_OUTPUT=$(swift build --show-bin-path"),
            "quick-deploy must capture show-bin-path output without masking swift build failures behind tail."
        )
        XCTAssertFalse(
            quickDeploy.contains("    tail -3 \"$BUILD_LOG\" || true\n    rm -f \"$BUILD_LOG\""),
            "quick-deploy must not reduce failed build output to only the last three lines."
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
