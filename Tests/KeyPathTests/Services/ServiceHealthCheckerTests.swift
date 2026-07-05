import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathInstallationWizard
import ServiceManagement
@preconcurrency import XCTest

final class ServiceHealthCheckerTests: XCTestCase {
    private var checker: ServiceHealthChecker!
    private var tempLaunchDaemonsDir: URL!
    private var originalLaunchDaemonsDir: String?
    private var originalSudoEnv: String?
    private var originalAllowAdminOperationsInTests = false
    private nonisolated(unsafe) var originalSMFactory: ((String) -> SMAppServiceProtocol)!
    private nonisolated(unsafe) var originalStatusProvider: SMAppServiceStatusProvider!

    override func setUp() async throws {
        try await super.setUp()
        originalStatusProvider = SMAppServiceStatusProvider.shared
        checker = await MainActor.run { ServiceHealthChecker.shared }
        // The shared singleton's 2s-TTL health cache can carry entries from
        // other suites in the same process (e.g. InstallerEngine tests that
        // probed services against a different launch-daemons dir). Clear it
        // so plist-existence checks here see this test's temp dir.
        checker.invalidateHealthCache()
        originalSMFactory = KanataDaemonManager.smServiceFactory
        originalSudoEnv = ProcessInfo.processInfo.environment["KEYPATH_USE_SUDO"]
        originalAllowAdminOperationsInTests = TestEnvironment.allowAdminOperationsInTests
        TestEnvironment.allowAdminOperationsInTests = false
        setenv("KEYPATH_USE_SUDO", "0", 1)

        tempLaunchDaemonsDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ServiceHealthCheckerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempLaunchDaemonsDir, withIntermediateDirectories: true)

        originalLaunchDaemonsDir = ProcessInfo.processInfo.environment["KEYPATH_LAUNCH_DAEMONS_DIR"]
        setenv("KEYPATH_LAUNCH_DAEMONS_DIR", tempLaunchDaemonsDir.path, 1)
        #if DEBUG
            ServiceHealthChecker.runtimeSnapshotOverride = nil
            ServiceHealthChecker.recentlyRestartedOverride = nil
            ServiceHealthChecker.inputCaptureStatusOverride = nil
            ServiceHealthChecker.vhidDriverExtensionEnabledOverride = nil
            ServiceHealthChecker.testForcedServiceHealth = nil
            KanataDaemonManager.registeredButNotLoadedOverride = nil
        #endif
    }

    override func tearDown() async throws {
        checker = nil
        KanataDaemonManager.smServiceFactory = originalSMFactory
        SMAppServiceStatusProvider.shared = originalStatusProvider
        TestEnvironment.allowAdminOperationsInTests = originalAllowAdminOperationsInTests
        if let originalSudoEnv {
            setenv("KEYPATH_USE_SUDO", originalSudoEnv, 1)
        } else {
            unsetenv("KEYPATH_USE_SUDO")
        }
        if let originalLaunchDaemonsDir {
            setenv("KEYPATH_LAUNCH_DAEMONS_DIR", originalLaunchDaemonsDir, 1)
        } else {
            unsetenv("KEYPATH_LAUNCH_DAEMONS_DIR")
        }
        #if DEBUG
            ServiceHealthChecker.runtimeSnapshotOverride = nil
            ServiceHealthChecker.recentlyRestartedOverride = nil
            ServiceHealthChecker.inputCaptureStatusOverride = nil
            ServiceHealthChecker.vhidDriverExtensionEnabledOverride = nil
            ServiceHealthChecker.testForcedServiceHealth = nil
            KanataDaemonManager.registeredButNotLoadedOverride = nil
        #endif
        try? FileManager.default.removeItem(at: tempLaunchDaemonsDir)
        tempLaunchDaemonsDir = nil
        originalLaunchDaemonsDir = nil
        originalSudoEnv = nil
        originalAllowAdminOperationsInTests = false
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

    private func writeVHIDPlist(
        programPath: String = PlistGenerator.vhidDaemonPath,
        processType: String? = "Interactive"
    ) throws {
        var dict: [String: Any] = [
            "ProgramArguments": [programPath]
        ]
        if let processType {
            dict["ProcessType"] = processType
        }
        let url = tempLaunchDaemonsDir.appendingPathComponent("\(ServiceHealthChecker.vhidDaemonServiceID).plist")
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: url)
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
            // Status now flows through the centralized provider (#853); point it at the
            // same enabled state so management-state determination sees .enabled.
            SMAppServiceStatusProvider.shared = SMAppServiceStatusProvider(
                cacheTTL: 0,
                serviceFactory: { _ in EnabledSMService() }
            )
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

    func testSystemExtensionsOutputShowsVHIDDriverEnabledOnlyForActivatedEnabled() {
        let enabled = """
        enabled active teamID bundleID (version) name [state]
            *    *    G43BCU2T37 org.pqrs.Karabiner-DriverKit-VirtualHIDDevice (1.8.0/1.8.0) org.pqrs.Karabiner-DriverKit-VirtualHIDDevice [activated enabled]
        """
        let disabled = """
        enabled active teamID bundleID (version) name [state]
            *    G43BCU2T37 org.pqrs.Karabiner-DriverKit-VirtualHIDDevice (1.8.0/1.8.0) org.pqrs.Karabiner-DriverKit-VirtualHIDDevice [activated disabled]
        """

        XCTAssertTrue(ServiceHealthChecker.systemExtensionsOutputShowsVHIDDriverEnabled(enabled))
        XCTAssertFalse(ServiceHealthChecker.systemExtensionsOutputShowsVHIDDriverEnabled(disabled))
    }

    func testRuntimeSnapshotReportsVHIDDriverNotActivatedBeforeKanataCrashLoop() async {
        #if DEBUG
            ServiceHealthChecker.vhidDriverExtensionEnabledOverride = { false }
            ServiceHealthChecker.inputCaptureStatusOverride = { .ready }
            ServiceHealthChecker.recentlyRestartedOverride = { _, _ in false }
        #endif

        let snapshot = await checker.checkKanataServiceRuntimeSnapshot(
            managementState: .smappserviceActive,
            staleEnabledRegistration: false,
            timeoutMs: 1
        )

        XCTAssertFalse(snapshot.inputCaptureReady)
        XCTAssertEqual(snapshot.inputCaptureIssue, ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason)
        XCTAssertEqual(
            ServiceHealthChecker.decideKanataHealth(for: snapshot),
            .unhealthy(reason: ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason)
        )
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

    func testDiagnoseDaemonStderrReturnsInputCaptureFailureForBuiltInKeyboard() async throws {
        let stderrURL = tempLaunchDaemonsDir.appendingPathComponent("kanata-stderr.log")
        try """
        [2026-03-07T13:21:14Z] IOHIDDeviceOpen error: (iokit/common) not permitted Apple Internal Keyboard / Trackpad
        """.write(to: stderrURL, atomically: true, encoding: .utf8)
        setenv("KEYPATH_KANATA_STDERR_PATH", stderrURL.path, 1)
        defer { unsetenv("KEYPATH_KANATA_STDERR_PATH") }

        let diagnosis = await checker.diagnoseDaemonStderr()
        XCTAssertFalse(diagnosis.permissionRejected)
        XCTAssertFalse(diagnosis.inputCapture.isReady)
        XCTAssertEqual(diagnosis.inputCapture.issue, ServiceHealthChecker.inputCaptureBuiltInKeyboardReason)
    }

    func testDiagnoseDaemonStderrDetectsVHIDDriverNotActivated() async throws {
        let stderrURL = tempLaunchDaemonsDir.appendingPathComponent("kanata-stderr.log")
        try """
        [kanata-launcher] Launching Kanata for user=test config=/Users/test/.config/keypath/keypath.kbd
        [ERROR] failed to open keyboard device(s): Karabiner-VirtualHIDDevice driver is not activated.
        Error: failed to open keyboard device(s): Karabiner-VirtualHIDDevice driver is not activated.
        """.write(to: stderrURL, atomically: true, encoding: .utf8)
        setenv("KEYPATH_KANATA_STDERR_PATH", stderrURL.path, 1)
        defer { unsetenv("KEYPATH_KANATA_STDERR_PATH") }

        let diagnosis = await checker.diagnoseDaemonStderr()
        XCTAssertFalse(diagnosis.permissionRejected)
        XCTAssertFalse(diagnosis.inputCapture.isReady)
        XCTAssertEqual(diagnosis.inputCapture.issue, ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason)
    }

    func testDiagnoseDaemonStderrDetectsAccessibilityRejection() async throws {
        let stderrURL = tempLaunchDaemonsDir.appendingPathComponent("kanata-stderr.log")
        try """
        [2026-03-07T13:21:14Z] kanata needs macOS Accessibility permission
        """.write(to: stderrURL, atomically: true, encoding: .utf8)
        setenv("KEYPATH_KANATA_STDERR_PATH", stderrURL.path, 1)
        defer { unsetenv("KEYPATH_KANATA_STDERR_PATH") }

        let diagnosis = await checker.diagnoseDaemonStderr()
        XCTAssertTrue(diagnosis.permissionRejected)
        // Input capture should be suppressed when AX is the root cause
        XCTAssertTrue(diagnosis.inputCapture.isReady)
    }

    func testKanataDecisionTreatsMissingInputCaptureAsUnhealthy() {
        let snapshot = ServiceHealthChecker.KanataServiceRuntimeSnapshot(
            managementState: .smappserviceActive,
            isRunning: true,
            isResponding: true,
            inputCaptureReady: false,
            inputCaptureIssue: ServiceHealthChecker.inputCaptureBuiltInKeyboardReason,
            launchctlExitCode: 0,
            staleEnabledRegistration: false,
            recentlyRestarted: false
        )

        let decision = ServiceHealthChecker.decideKanataHealth(for: snapshot)
        XCTAssertEqual(decision, .unhealthy(reason: ServiceHealthChecker.inputCaptureBuiltInKeyboardReason))
        XCTAssertFalse(decision.isHealthy)
    }

    func testIsKanataPlistInstalledUsesLaunchDaemonsOverride() throws {
        try writeEmptyPlist(serviceID: ServiceHealthChecker.kanataServiceID)
        XCTAssertTrue(checker.isKanataPlistInstalled())
    }

    func testIsVHIDDaemonConfiguredCorrectlyReadsProgramArguments() throws {
        try writeVHIDPlist()
        XCTAssertTrue(checker.isVHIDDaemonConfiguredCorrectly())
    }

    func testIsVHIDDaemonConfiguredCorrectlyReturnsFalseForWrongPath() throws {
        try writeVHIDPlist(programPath: "/wrong/path")
        XCTAssertFalse(checker.isVHIDDaemonConfiguredCorrectly())
    }

    /// Plists from before the MAL-57 starvation fix lack ProcessType=Interactive
    /// and must report misconfigured so repair rewrites them.
    func testIsVHIDDaemonConfiguredCorrectlyReturnsFalseWithoutProcessType() throws {
        try writeVHIDPlist(processType: nil)
        XCTAssertFalse(checker.isVHIDDaemonConfiguredCorrectly())
    }

    // MARK: - isVHIDDaemonPlistPresentButMisconfigured (proactive MAL-57 migration)

    /// No plist at all is "services not installed", not "misconfigured" —
    /// that case is owned by service health, not the plist-content check.
    func testVHIDPlistMisconfiguredReturnsFalseWhenPlistMissing() {
        XCTAssertFalse(checker.isVHIDDaemonPlistPresentButMisconfigured())
    }

    func testVHIDPlistMisconfiguredReturnsFalseForCorrectPlist() throws {
        try writeVHIDPlist()
        XCTAssertFalse(checker.isVHIDDaemonPlistPresentButMisconfigured())
    }

    /// A pre-MAL-57 plist (exists, correct path, no ProcessType=Interactive)
    /// must report misconfigured so existing installs migrate via repair.
    func testVHIDPlistMisconfiguredReturnsTrueWithoutProcessType() throws {
        try writeVHIDPlist(processType: nil)
        XCTAssertTrue(checker.isVHIDDaemonPlistPresentButMisconfigured())
    }

    func testVHIDPlistMisconfiguredReturnsTrueForWrongProgramPath() throws {
        try writeVHIDPlist(programPath: "/wrong/path")
        XCTAssertTrue(checker.isVHIDDaemonPlistPresentButMisconfigured())
    }

    /// A present-but-unparseable plist is misconfigured (repair rewrites it),
    /// not "missing" — only true absence is owned by service health.
    func testVHIDPlistMisconfiguredReturnsTrueForCorruptPlist() throws {
        let url = tempLaunchDaemonsDir.appendingPathComponent(
            "\(ServiceHealthChecker.vhidDaemonServiceID).plist"
        )
        try Data("not a plist".utf8).write(to: url)
        XCTAssertTrue(checker.isVHIDDaemonPlistPresentButMisconfigured())
    }
}
