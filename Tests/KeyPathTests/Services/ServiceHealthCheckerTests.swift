import Foundation
@testable import KeyPathAppKit
import ServiceManagement
@preconcurrency import XCTest

final class ServiceHealthCheckerTests: XCTestCase {
    private var checker: ServiceHealthChecker!
    private var tempLaunchDaemonsDir: URL!
    private var originalLaunchDaemonsDir: String?
    private nonisolated(unsafe) var originalSMFactory: ((String) -> SMAppServiceProtocol)!

    override func setUp() async throws {
        try await super.setUp()
        checker = ServiceHealthChecker.shared
        originalSMFactory = KanataDaemonManager.smServiceFactory

        tempLaunchDaemonsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ServiceHealthCheckerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempLaunchDaemonsDir, withIntermediateDirectories: true)

        originalLaunchDaemonsDir = ProcessInfo.processInfo.environment["KEYPATH_LAUNCH_DAEMONS_DIR"]
        setenv("KEYPATH_LAUNCH_DAEMONS_DIR", tempLaunchDaemonsDir.path, 1)
        #if DEBUG
            ServiceHealthChecker.runtimeSnapshotOverride = nil
            ServiceHealthChecker.recentlyRestartedOverride = nil
            ServiceHealthChecker.inputCaptureStatusOverride = nil
            KanataDaemonManager.registeredButNotLoadedOverride = nil
        #endif
    }

    override func tearDown() async throws {
        checker = nil
        KanataDaemonManager.smServiceFactory = originalSMFactory
        if let originalLaunchDaemonsDir {
            setenv("KEYPATH_LAUNCH_DAEMONS_DIR", originalLaunchDaemonsDir, 1)
        } else {
            unsetenv("KEYPATH_LAUNCH_DAEMONS_DIR")
        }
        #if DEBUG
            ServiceHealthChecker.runtimeSnapshotOverride = nil
            ServiceHealthChecker.recentlyRestartedOverride = nil
            ServiceHealthChecker.inputCaptureStatusOverride = nil
            KanataDaemonManager.registeredButNotLoadedOverride = nil
        #endif
        try? FileManager.default.removeItem(at: tempLaunchDaemonsDir)
        tempLaunchDaemonsDir = nil
        originalLaunchDaemonsDir = nil
        originalSMFactory = nil
        try await super.tearDown()
    }

    private final class EnabledSMService: SMAppServiceProtocol, @unchecked Sendable {
        var status: SMAppService.Status = .enabled

        func register() throws {}
        func unregister() async throws {}
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

    func testIsServiceLoadedReturnsFalseWhenSMAppServiceEnabledButStale() async {
#if DEBUG
            KanataDaemonManager.smServiceFactory = { _ in EnabledSMService() }
            KanataDaemonManager.registeredButNotLoadedOverride = { true }
#endif

        let loaded = await checker.isServiceLoaded(serviceID: ServiceHealthChecker.kanataServiceID)
        XCTAssertFalse(loaded, "Enabled-but-stale SMAppService registration should not be treated as loaded")
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

    func testKanataDecisionNotFoundWithoutRuntimeIsUnhealthy() {
        let snapshot = ServiceHealthChecker.KanataServiceRuntimeSnapshot(
            managementState: .smappserviceActive,
            isRunning: false,
            isResponding: false,
            inputCaptureReady: true,
            inputCaptureIssue: nil,
            launchctlExitCode: 113,
            staleEnabledRegistration: false,
            recentlyRestarted: true
        )

        let decision = ServiceHealthChecker.decideKanataHealth(for: snapshot)
        XCTAssertEqual(decision, .unhealthy(reason: "launchctl-not-found-without-runtime"))
        XCTAssertFalse(decision.isHealthy)
    }

    func testKanataDecisionRunningWithTcpWarmupIsTransientHealthy() {
        let snapshot = ServiceHealthChecker.KanataServiceRuntimeSnapshot(
            managementState: .smappserviceActive,
            isRunning: true,
            isResponding: false,
            inputCaptureReady: true,
            inputCaptureIssue: nil,
            launchctlExitCode: 0,
            staleEnabledRegistration: false,
            recentlyRestarted: true
        )

        let decision = ServiceHealthChecker.decideKanataHealth(for: snapshot)
        XCTAssertEqual(decision, .transient(reason: "tcp-warmup-after-restart"))
        XCTAssertTrue(decision.isHealthy)
    }

    func testKanataDecisionStaleRegistrationIsUnhealthy() {
        let snapshot = ServiceHealthChecker.KanataServiceRuntimeSnapshot(
            managementState: .smappserviceActive,
            isRunning: false,
            isResponding: false,
            inputCaptureReady: true,
            inputCaptureIssue: nil,
            launchctlExitCode: nil,
            staleEnabledRegistration: true,
            recentlyRestarted: false
        )

        let decision = ServiceHealthChecker.decideKanataHealth(for: snapshot)
        XCTAssertEqual(decision, .unhealthy(reason: "stale-enabled-registration"))
        XCTAssertFalse(decision.isHealthy)
    }

    func testKanataDecisionRunningAndRespondingWinsOverStaleMetadata() {
        let snapshot = ServiceHealthChecker.KanataServiceRuntimeSnapshot(
            managementState: .smappserviceActive,
            isRunning: true,
            isResponding: true,
            inputCaptureReady: true,
            inputCaptureIssue: nil,
            launchctlExitCode: 0,
            staleEnabledRegistration: true,
            recentlyRestarted: false
        )

        let decision = ServiceHealthChecker.decideKanataHealth(for: snapshot)
        XCTAssertEqual(decision, .healthy)
        XCTAssertTrue(decision.isHealthy)
    }

    func testCheckKanataInputCaptureStatusReturnsNotReadyForBuiltInKeyboardPermissionError() async throws {
        let stderrURL = tempLaunchDaemonsDir.appendingPathComponent("kanata-stderr.log")
        try """
        [2026-03-07T13:21:14Z] IOHIDDeviceOpen error: (iokit/common) not permitted Apple Internal Keyboard / Trackpad
        """.write(to: stderrURL, atomically: true, encoding: .utf8)
        setenv("KEYPATH_KANATA_STDERR_PATH", stderrURL.path, 1)
        defer { unsetenv("KEYPATH_KANATA_STDERR_PATH") }

        let status = await checker.checkKanataInputCaptureStatus()
        XCTAssertFalse(status.isReady)
        XCTAssertEqual(status.issue, "kanata-cannot-open-built-in-keyboard")
    }

    func testKanataDecisionTreatsMissingInputCaptureAsUnhealthy() {
        let snapshot = ServiceHealthChecker.KanataServiceRuntimeSnapshot(
            managementState: .smappserviceActive,
            isRunning: true,
            isResponding: true,
            inputCaptureReady: false,
            inputCaptureIssue: "kanata-cannot-open-built-in-keyboard",
            launchctlExitCode: 0,
            staleEnabledRegistration: false,
            recentlyRestarted: false
        )

        let decision = ServiceHealthChecker.decideKanataHealth(for: snapshot)
        XCTAssertEqual(decision, .unhealthy(reason: "kanata-cannot-open-built-in-keyboard"))
        XCTAssertFalse(decision.isHealthy)
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
