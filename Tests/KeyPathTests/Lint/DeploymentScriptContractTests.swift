import Foundation
import XCTest

final class DeploymentScriptContractTests: XCTestCase {
    func testUninstallerPathsTrackAppResources() throws {
        let root = repositoryRoot()
        let entryPoint = root.appendingPathComponent("Scripts/uninstall.sh")
        let expectedDestination = "../Sources/KeyPathApp/Resources/uninstall.sh"
        let coordinator = try contents(
            of: root.appendingPathComponent("Sources/KeyPathAppKit/Managers/UninstallCoordinator.swift")
        )
        let buildAndSign = try contents(of: root.appendingPathComponent("Scripts/build-and-sign.sh"))

        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: entryPoint.path),
            expectedDestination,
            "Scripts/uninstall.sh must remain a relative link to the current app resource."
        )
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: entryPoint.path),
            "Scripts/uninstall.sh must resolve to an executable file."
        )
        XCTAssertTrue(coordinator.contains("Sources/KeyPathApp/Resources/uninstall.sh"))
        XCTAssertFalse(coordinator.contains("Sources/KeyPath/Resources/uninstall.sh"))
        XCTAssertTrue(buildAndSign.contains("Sources/KeyPathApp/Resources directory not found"))
        XCTAssertFalse(buildAndSign.contains("Sources/KeyPath/Resources directory not found"))
    }

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
        XCTAssertTrue(xcodeContract.contains(#"KEYPATH_STABLE_XCODE_VERSION="${KEYPATH_STABLE_XCODE_VERSION:-26.6}""#))
        XCTAssertTrue(xcodeContract.contains("/Applications/Xcode.app/Contents/Developer"))
        XCTAssertTrue(xcodeContract.contains("keypath_xcode_version"))
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

    func testReleaseBuildReadsVersionMetadataFromPlistPaths() throws {
        let root = repositoryRoot()
        let buildAndSign = try contents(of: root.appendingPathComponent("Scripts/build-and-sign.sh"))

        XCTAssertTrue(
            buildAndSign.contains(#"PlistBuddy -c "Print :CFBundleVersion" "$CONTENTS/Info.plist""#),
            "Release metadata must read the assembled app plist as a file path."
        )
        XCTAssertFalse(
            buildAndSign.contains(#"defaults read "$CONTENTS/Info""#),
            "A relative path passed to defaults is interpreted as a preferences domain and falls back to build 0."
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

    func testLocalBuildsSharePinnedWorktreeCache() throws {
        let root = repositoryRoot()
        let quickDeploy = try contents(of: root.appendingPathComponent("Scripts/quick-deploy.sh"))
        let safeTests = try contents(of: root.appendingPathComponent("Scripts/run-tests-safe.sh"))
        let cacheContract = try contents(of: root.appendingPathComponent("Scripts/lib/build-cache.sh"))

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.resolved").path),
            "SwiftPM dependencies must be pinned for repeatable fresh-worktree builds."
        )
        XCTAssertTrue(
            safeTests.contains(#"SCRATCH_PATH=${SCRATCH_PATH:-"$PROJECT_DIR/.build"}"#),
            "Local tests must reuse the worktree's canonical .build graph."
        )
        XCTAssertTrue(
            safeTests.contains(#"TEST_RESET_MODULE_CACHE="${KEYPATH_TEST_RESET_MODULE_CACHE:-0}""#),
            "The safe runner must preserve the module cache unless reset is explicitly requested."
        )
        XCTAssertTrue(
            quickDeploy.contains("swift build --disable-automatic-resolution")
                && safeTests.contains("swift build --disable-automatic-resolution"),
            "Routine build and test entry points must honor Package.resolved without re-resolving."
        )
        XCTAssertTrue(
            quickDeploy.contains(#"source "$SCRIPT_DIR/lib/build-cache.sh""#)
                && safeTests.contains(#"source "$SCRIPT_DIR/lib/build-cache.sh""#)
                && cacheContract.contains(#"if [[ -L "$scratch_path/debug" ]]"#),
            "Build entry points must safely refresh only generated debug symlinks."
        )
        XCTAssertTrue(
            quickDeploy.contains(#"PROJECT_DIR=$(cd "$SCRIPT_DIR/.." >/dev/null && pwd -P)"#),
            "quick-deploy must canonicalize PROJECT_DIR so Clang sees one module-cache path."
        )
        XCTAssertTrue(
            cacheContract.contains(".keypath-canonical-module-cache-v1")
                && cacheContract.contains("swift package clean"),
            "Legacy noncanonical modules require one marker-gated artifact migration."
        )
    }

    func testSafeTestFailuresAlwaysPrintArtifactPaths() throws {
        let root = repositoryRoot()
        let safeTests = try contents(of: root.appendingPathComponent("Scripts/run-tests-safe.sh"))

        XCTAssertTrue(safeTests.contains("print_failure_log_paths()"))
        XCTAssertTrue(safeTests.contains(#"Full test log: ${LOG:-not-created}"#))
        XCTAssertTrue(safeTests.contains(#"Full build log: ${BUILD_LOG:-not-created}"#))
        XCTAssertEqual(
            safeTests.components(separatedBy: "print_failure_log_paths\n").count - 1,
            6,
            "Every build, timeout, crash, parsed-failure, and unexplained nonzero exit must print artifact paths."
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
