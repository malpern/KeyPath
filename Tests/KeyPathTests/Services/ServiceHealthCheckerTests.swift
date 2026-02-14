import Foundation
@testable import KeyPathAppKit
@preconcurrency import XCTest

final class ServiceHealthCheckerTests: XCTestCase {
    private var checker: ServiceHealthChecker!
    private var tempLaunchDaemonsDir: URL!
    private var originalLaunchDaemonsDir: String?

    override func setUp() async throws {
        try await super.setUp()
        checker = ServiceHealthChecker.shared

        tempLaunchDaemonsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ServiceHealthCheckerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempLaunchDaemonsDir, withIntermediateDirectories: true)

        originalLaunchDaemonsDir = ProcessInfo.processInfo.environment["KEYPATH_LAUNCH_DAEMONS_DIR"]
        setenv("KEYPATH_LAUNCH_DAEMONS_DIR", tempLaunchDaemonsDir.path, 1)
    }

    override func tearDown() async throws {
        checker = nil
        if let originalLaunchDaemonsDir {
            setenv("KEYPATH_LAUNCH_DAEMONS_DIR", originalLaunchDaemonsDir, 1)
        } else {
            unsetenv("KEYPATH_LAUNCH_DAEMONS_DIR")
        }
        try? FileManager.default.removeItem(at: tempLaunchDaemonsDir)
        tempLaunchDaemonsDir = nil
        originalLaunchDaemonsDir = nil
        try await super.tearDown()
    }

    private func writeEmptyPlist(serviceID: String) throws {
        let url = tempLaunchDaemonsDir.appendingPathComponent("\(serviceID).plist")
        FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
    }

    private func writeVHIDPlist(programPath: String) throws {
        let dict: NSDictionary = [
            "ProgramArguments": [programPath]
        ]
        let url = tempLaunchDaemonsDir.appendingPathComponent("\(ServiceHealthChecker.vhidDaemonServiceID).plist")
        XCTAssertTrue(dict.write(to: url, atomically: true))
    }

    func testServiceIdentifiers() {
        XCTAssertEqual(ServiceHealthChecker.kanataServiceID, "com.keypath.kanata")
        XCTAssertEqual(ServiceHealthChecker.vhidDaemonServiceID, "com.keypath.karabiner-vhiddaemon")
        XCTAssertEqual(ServiceHealthChecker.vhidManagerServiceID, "com.keypath.karabiner-vhidmanager")
    }

    func testIsServiceLoadedUsesPlistExistenceInTestMode() async throws {
        try writeEmptyPlist(serviceID: ServiceHealthChecker.kanataServiceID)
        let loaded = await checker.isServiceLoaded(serviceID: ServiceHealthChecker.kanataServiceID)
        XCTAssertTrue(loaded)
    }

    func testIsServiceLoadedReturnsFalseForInvalidServiceID() async {
        let loaded = await checker.isServiceLoaded(serviceID: "com.keypath.invalid-service")
        XCTAssertFalse(loaded)
    }

    func testIsServiceLoadedForVHIDServicesUsesPlistExistenceInTestMode() async throws {
        try writeEmptyPlist(serviceID: ServiceHealthChecker.vhidDaemonServiceID)
        try writeEmptyPlist(serviceID: ServiceHealthChecker.vhidManagerServiceID)

        let daemonLoaded = await checker.isServiceLoaded(serviceID: ServiceHealthChecker.vhidDaemonServiceID)
        let managerLoaded = await checker.isServiceLoaded(serviceID: ServiceHealthChecker.vhidManagerServiceID)
        XCTAssertTrue(daemonLoaded)
        XCTAssertTrue(managerLoaded)
    }

    func testIsServiceHealthyUsesPlistExistenceInTestMode() async throws {
        try writeEmptyPlist(serviceID: ServiceHealthChecker.kanataServiceID)
        let healthy = await checker.isServiceHealthy(serviceID: ServiceHealthChecker.kanataServiceID)
        XCTAssertTrue(healthy)
    }

    func testIsServiceHealthyReturnsFalseForInvalidServiceID() async {
        let healthy = await checker.isServiceHealthy(serviceID: "com.keypath.invalid-service")
        XCTAssertFalse(healthy)
    }

    func testCheckKanataServiceHealthDoesNotProbeSystemInTestMode() async {
        let health = await checker.checkKanataServiceHealth()
        XCTAssertFalse(health.isRunning)
        XCTAssertFalse(health.isResponding)
    }

    func testIsKanataPlistInstalledUsesLaunchDaemonsOverride() throws {
        try writeEmptyPlist(serviceID: ServiceHealthChecker.kanataServiceID)
        XCTAssertTrue(checker.isKanataPlistInstalled())
    }

    func testIsVHIDDaemonConfiguredCorrectlyReadsProgramArguments() throws {
        let expectedPath =
            "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
        try writeVHIDPlist(programPath: expectedPath)
        XCTAssertTrue(checker.isVHIDDaemonConfiguredCorrectly())
    }

    func testIsVHIDDaemonConfiguredCorrectlyReturnsFalseForWrongPath() throws {
        try writeVHIDPlist(programPath: "/wrong/path")
        XCTAssertFalse(checker.isVHIDDaemonConfiguredCorrectly())
    }
}
