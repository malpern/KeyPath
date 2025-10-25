import XCTest
@testable import KeyPath

/// Focused tests to harden ProcessLifecycleManager behavior that Task 1 depends on
final class ProcessLifecycleManagerRoundTripTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        // Isolate PID file path under a temp HOME so we don’t touch the user’s real files
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kp-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        setenv("HOME", tempHome.path, 1)
        try? PIDFileManager.removePID()
    }

    override func tearDownWithError() throws {
        try? PIDFileManager.removePID()
        try? FileManager.default.removeItem(at: tempHome)
    }

    @MainActor
    func testRegisterThenUnregisterProcessUpdatesPIDFile() async throws {
        let mgr = ProcessLifecycleManager()
        let myPid = getpid()

        // Register should create the PID file and set ownedPID
        await mgr.registerStartedProcess(pid: myPid, command: "KeyPathTests")

        let record = PIDFileManager.readPID()
        XCTAssertNotNil(record, "PID file should be written on register")
        XCTAssertEqual(record?.pid, myPid, "PID file should contain the registered PID")

        // Unregister should remove PID file and clear ownership
        await mgr.unregisterProcess()
        XCTAssertNil(PIDFileManager.readPID(), "PID file should be removed on unregister")
    }
}

