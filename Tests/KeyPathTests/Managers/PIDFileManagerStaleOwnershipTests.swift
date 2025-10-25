import XCTest
@testable import KeyPath

/// Validates stale PID ownership semantics used by ProcessLifecycleManager
final class PIDFileManagerStaleOwnershipTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kp-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        setenv("HOME", tempHome.path, 1)
        try? PIDFileManager.removePID()
    }

    override func tearDownWithError() throws {
        try? PIDFileManager.removePID()
        try? FileManager.default.removeItem(at: tempHome)
    }

    func testCheckOwnershipReturnsOrphanWhenRecordIsStaleButProcessAlive() throws {
        // Craft a stale record (> 1 hour old) for a live PID
        let stale = PIDFileManager.PIDRecord(
            pid: getpid(),
            startTime: Date(timeIntervalSinceNow: -7200),
            command: "KeyPathTests",
            bundleIdentifier: "com.keypath.KeyPath"
        )
        let encoder = JSONEncoder()
        try encoder.encode(stale).write(to: URL(fileURLWithPath: PIDFileManager.pidFilePath))

        let ownership = PIDFileManager.checkOwnership()
        XCTAssertFalse(ownership.owned, "Stale record should not be considered owned")
        XCTAssertEqual(ownership.pid, stale.pid, "Should expose PID of stale/orphaned process")
    }
}

