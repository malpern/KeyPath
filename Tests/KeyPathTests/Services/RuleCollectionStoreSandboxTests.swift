import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
import XCTest

/// Regression coverage for the concurrency root cause behind the CLIPackCRUDTests
/// "could not enable associated rule collection" failures: under test,
/// RuleCollectionStore's default file must live in the per-process AppPaths
/// sandbox, never the real ~/.config/keypath. Otherwise concurrent test
/// processes (parallel CI PRs, or multiple local Claude sessions) race the same
/// RuleCollections.json. See RuleCollectionStore.init.
final class RuleCollectionStoreSandboxTests: XCTestCase {
    func testDefaultStoreResolvesIntoPerProcessSandbox() async {
        // AppPaths sandbox is per-process: keypath-tests-<pid>/.config/keypath
        let expectedDir = AppPaths.configDirectory.path
        let sandboxRoot = AppPaths.testSandboxDirectory.path

        // The default store (no injected fileURL) must resolve under the sandbox.
        let url = await RuleCollectionStore().debugFileURL
        XCTAssertTrue(
            url.path.hasPrefix(sandboxRoot),
            "RuleCollectionStore must write inside the per-process test sandbox, got \(url.path)"
        )
        XCTAssertEqual(url.deletingLastPathComponent().path, expectedDir)
        XCTAssertEqual(url.lastPathComponent, "RuleCollections.json")
        XCTAssertFalse(
            url.path.contains(NSHomeDirectory() + "/.config/keypath"),
            "Default store must not touch the real ~/.config/keypath during tests"
        )
    }
}
