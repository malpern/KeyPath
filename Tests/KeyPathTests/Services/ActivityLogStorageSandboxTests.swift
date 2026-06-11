import KeyPathCore
@testable import KeyPathInsights
import XCTest

/// Guards against activity-log tests writing to (or deleting from) the real
/// `~/Library/Application Support/KeyPath/ActivityLog` directory. The storage
/// path must resolve through `AppPaths`, which redirects into a per-process
/// temp sandbox while tests run. A regression here means any test touching
/// `ActivityLogStorage.shared` can pollute or destroy genuine activity logs.
final class ActivityLogStorageSandboxTests: XCTestCase {
    private var realSupportDir: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/KeyPath", isDirectory: true).path
    }

    func testDefaultBaseDirectoryIsSandboxed() {
        // The redirect only engages when test detection works; assert it first
        // so a detection regression fails loudly instead of vacuously passing.
        XCTAssertTrue(TestEnvironment.isRunningTests)

        let dir = ActivityLogStorage.defaultBaseDirectory.standardizedFileURL
        let sandbox = AppPaths.testSandboxDirectory.standardizedFileURL
        XCTAssertTrue(
            dir.path.hasPrefix(sandbox.path),
            "\(dir.path) must live under the test sandbox \(sandbox.path)"
        )
        XCTAssertFalse(
            dir.path.hasPrefix(realSupportDir),
            "\(dir.path) must not point at the real Application Support directory during tests"
        )
        XCTAssertEqual(dir.lastPathComponent, "ActivityLog")
    }

    func testKeychainServiceIsSandboxed() {
        // clearAll() deletes the encryption key; during tests that must target
        // a separate Keychain item, never the production key.
        XCTAssertEqual(ActivityLogEncryption.keychainService, "com.keypath.activitylog.tests")
    }
}
