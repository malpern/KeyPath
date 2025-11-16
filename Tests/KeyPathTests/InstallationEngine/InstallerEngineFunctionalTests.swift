import Darwin
import Foundation
import ServiceManagement
import XCTest

@testable import KeyPath
@testable import KeyPathCore

@MainActor
final class InstallerEngineFunctionalTests: XCTestCase {
    private var sandboxURL: URL!
    private var launchDaemonsURL: URL!
    private var homeURL: URL!
    private var previousEnv: [String: String?] = [:]
    private var originalSMFactory: ((String) -> SMAppServiceProtocol)!
    private var smService: TestSMAppService!
    private var originalLogDirectory: String?

    override func setUp() async throws {
        try await super.setUp()

        sandboxURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("installer-engine-\(UUID().uuidString)", isDirectory: true)
        launchDaemonsURL = sandboxURL.appendingPathComponent("Library/LaunchDaemons", isDirectory: true)
        homeURL = sandboxURL.appendingPathComponent("Users/tester", isDirectory: true)

        try FileManager.default.createDirectory(at: launchDaemonsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)

        setEnv("KEYPATH_TEST_ROOT", sandboxURL.path)
        setEnv("KEYPATH_LAUNCH_DAEMONS_DIR", launchDaemonsURL.path)
        setEnv("KEYPATH_TEST_MODE", "1")
        setEnv("HOME", homeURL.path)
        setEnv("KEYPATH_HOME_DIR_OVERRIDE", homeURL.path)

        TestEnvironment.allowAdminOperationsInTests = true

        let logDir = homeURL
            .appendingPathComponent("Library/Logs/KeyPath", isDirectory: true)
        setEnv("KEYPATH_LOG_DIR_OVERRIDE", logDir.path)
        originalLogDirectory = AppLogger.shared.currentLogDirectory()
        AppLogger.shared.overrideLogDirectory(logDir.path)

        originalSMFactory = KanataDaemonManager.smServiceFactory
        smService = TestSMAppService(initialStatus: .notRegistered)
        KanataDaemonManager.smServiceFactory = { _ in self.smService }
    }

    override func tearDown() async throws {
        KanataDaemonManager.smServiceFactory = originalSMFactory
        TestEnvironment.allowAdminOperationsInTests = false
        if let originalLogDirectory {
            AppLogger.shared.overrideLogDirectory(originalLogDirectory)
        }
        restoreEnv()

        if let sandboxURL, FileManager.default.fileExists(atPath: sandboxURL.path) {
            try? FileManager.default.removeItem(at: sandboxURL)
        }

        smService = nil
        sandboxURL = nil
        launchDaemonsURL = nil
        homeURL = nil
        originalLogDirectory = nil
        try await super.tearDown()
    }

    func testFirstTimeInstallProvisioningFlow() async throws {
        let installer = LaunchDaemonInstaller()

        let createResult = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(createResult)
        let loadResult = await installer.loadServices()
        XCTAssertTrue(loadResult)

        for id in Self.serviceIDs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: plistPath(for: id)), "Missing plist for \(id)")
        }

        let status = await MainActor.run { installer.getServiceStatus() }
        XCTAssertTrue(status.allServicesLoaded)
        XCTAssertTrue(status.allServicesHealthy)
    }

    func testReRunningInstallerDoesNotChangeExistingServiceDefinitions() async throws {
        let installer = LaunchDaemonInstaller()
        let firstCreateResult = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(firstCreateResult)

        let initialContents = try loadServiceContents()

        let secondCreateResult = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(secondCreateResult)
        let secondContents = try loadServiceContents()

        XCTAssertEqual(initialContents, secondContents)
    }

    func testReRunningInstallerFailsWhenLaunchDaemonDirectoryReadOnly() async throws {
        let installer = LaunchDaemonInstaller()
        let firstRun = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(firstRun)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: launchDaemonsURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launchDaemonsURL.path)
        }

        let secondCreateResult = await installer.createAllLaunchDaemonServices()
        XCTAssertFalse(secondCreateResult)

        try await waitForLogFlush()
        let logs = try readInstallerLog()
        XCTAssertTrue(
            logs.contains("Failed to install plists"),
            "Expected failure log when second installation cannot overwrite launch daemon directory"
        )
    }

    func testReRunningInstallerFailsWhenDuplicatePlistDirectoryExists() async throws {
        let installer = LaunchDaemonInstaller()
        let firstRun = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(firstRun)

        try FileManager.default.removeItem(at: launchDaemonsURL)
        FileManager.default.createFile(atPath: launchDaemonsURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: launchDaemonsURL) }

        let secondCreateResult = await installer.createAllLaunchDaemonServices()
        XCTAssertFalse(secondCreateResult)

        try await waitForLogFlush()
        let logs = try readInstallerLog()
        XCTAssertTrue(
            logs.contains("Failed to install plists"),
            "A leftover file blocking the LaunchDaemons directory should surface a failure message"
        )
    }

    func testInstallerLogsPermissionDeniedWhenConfigDirectoryCannotBeCreated() async throws {
        let installer = LaunchDaemonInstaller()
        let configDir = homeURL.appendingPathComponent(".config", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: configDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: configDir.path)
        }

        let result = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(result)

        try await waitForLogFlush()
        let logs = try readInstallerLog()
        XCTAssertTrue(
            logs.contains("Failed to create default user config"),
            "Permission denial when creating ~/.config/keypath should be logged"
        )
    }

    func testMissingVirtualHIDServiceTriggersReinstall() async throws {
        let installer = LaunchDaemonInstaller()
        let firstCreateResult = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(firstCreateResult)

        let missingPath = plistPath(for: "com.keypath.karabiner-vhidmanager")
        try FileManager.default.removeItem(atPath: missingPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingPath))

        let secondCreateResult = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(secondCreateResult)
        XCTAssertTrue(FileManager.default.fileExists(atPath: missingPath))
    }

    func testSMAppServiceRegistrationFailureIsSurfaced() async {
        smService.shouldFailRegistration = true
        let installer = LaunchDaemonInstaller()

        let result = await installer.createKanataLaunchDaemon()
        XCTAssertFalse(result)
        XCTAssertEqual(smService.registerCallCount, 1)
        XCTAssertEqual(smService.status, .notRegistered)
    }

    func testMissingKanataServiceTriggersReinstall() async throws {
        let installer = LaunchDaemonInstaller()
        let firstCreateResult = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(firstCreateResult)

        let kanataPath = plistPath(for: "com.keypath.kanata")
        try FileManager.default.removeItem(atPath: kanataPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: kanataPath))

        let secondCreateResult = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(secondCreateResult)
        XCTAssertTrue(FileManager.default.fileExists(atPath: kanataPath))
    }

    func testLoadServicesFailsWhenServiceDefinitionMissing() async throws {
        let installer = LaunchDaemonInstaller()
        let createResult = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(createResult)
        try FileManager.default.removeItem(atPath: plistPath(for: "com.keypath.kanata"))

        let loadResult = await installer.loadServices()
        XCTAssertFalse(loadResult)

        let status = await MainActor.run { installer.getServiceStatus() }
        XCTAssertFalse(status.kanataServiceLoaded)
        XCTAssertFalse(status.allServicesHealthy)
    }

    func testRepairFlowRestoresMissingVhidServices() async throws {
        let installer = LaunchDaemonInstaller()
        let initialInstall = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(initialInstall)
        let initialLoad = await installer.loadServices()
        XCTAssertTrue(initialLoad)

        let vhidIDs = ["com.keypath.karabiner-vhiddaemon", "com.keypath.karabiner-vhidmanager"]
        for id in vhidIDs {
            try FileManager.default.removeItem(atPath: plistPath(for: id))
        }

        let degradedStatus = await MainActor.run { installer.getServiceStatus() }
        XCTAssertFalse(degradedStatus.vhidDaemonServiceLoaded)
        XCTAssertFalse(degradedStatus.vhidManagerServiceLoaded)

        let repairInstall = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(repairInstall)
        let repairLoad = await installer.loadServices()
        XCTAssertTrue(repairLoad)

        for id in vhidIDs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: plistPath(for: id)))
        }

        let repairedStatus = await MainActor.run { installer.getServiceStatus() }
        XCTAssertTrue(repairedStatus.allServicesLoaded)
        XCTAssertTrue(repairedStatus.allServicesHealthy)
    }

    func testServiceStatusDetectsMissingVhidManager() async throws {
        let installer = LaunchDaemonInstaller()
        let installResult = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(installResult)
        let loadResult = await installer.loadServices()
        XCTAssertTrue(loadResult)

        try FileManager.default.removeItem(atPath: plistPath(for: "com.keypath.karabiner-vhidmanager"))

        let status = await MainActor.run { installer.getServiceStatus() }
        XCTAssertTrue(status.vhidDaemonServiceLoaded)
        XCTAssertFalse(status.vhidManagerServiceLoaded)
        XCTAssertFalse(status.allServicesHealthy)
    }

    func testRestartUnhealthyServicesRepairsMissingVhidServices() async throws {
        let installer = LaunchDaemonInstaller()
        let installResult = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(installResult)
        let loadResult = await installer.loadServices()
        XCTAssertTrue(loadResult)

        let vhidIDs = ["com.keypath.karabiner-vhiddaemon", "com.keypath.karabiner-vhidmanager"]
        for id in vhidIDs {
            try FileManager.default.removeItem(atPath: plistPath(for: id))
        }

        let degradedStatus = await MainActor.run { installer.getServiceStatus() }
        XCTAssertFalse(degradedStatus.vhidDaemonServiceLoaded)
        XCTAssertFalse(degradedStatus.vhidManagerServiceLoaded)

        let restartResult = await installer.restartUnhealthyServices()
        XCTAssertTrue(restartResult)

        for id in vhidIDs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: plistPath(for: id)))
        }

        let repairedStatus = await MainActor.run { installer.getServiceStatus() }
        XCTAssertTrue(repairedStatus.vhidDaemonServiceLoaded)
        XCTAssertTrue(repairedStatus.vhidManagerServiceLoaded)
        XCTAssertTrue(repairedStatus.vhidDaemonServiceHealthy)
        XCTAssertTrue(repairedStatus.vhidManagerServiceHealthy)
        XCTAssertTrue(repairedStatus.kanataServiceLoaded)
        XCTAssertFalse(repairedStatus.kanataServiceHealthy, "Kanata process isn't running under tests, so health should reflect that state")
    }

    func testCreateAllServicesLogsErrorWhenUserConfigDirectoryBlocked() async throws {
        let installer = LaunchDaemonInstaller()
        let configDir = homeURL.appendingPathComponent(".config/keypath", isDirectory: true)
        let configFile = configDir.appendingPathComponent("keypath.kbd")
        try? FileManager.default.removeItem(at: configDir)
        try? FileManager.default.createDirectory(at: homeURL.appendingPathComponent(".config", isDirectory: true), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: configDir)
        FileManager.default.createFile(atPath: configDir.path, contents: Data())
        defer {
            try? FileManager.default.removeItem(at: configDir)
            try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        }

        let previousLogDir = AppLogger.shared.currentLogDirectory()
        let tempLogDir = homeURL
            .appendingPathComponent("Library/Logs/KeyPath", isDirectory: true)
            .appendingPathComponent("config-permission-\(UUID().uuidString)", isDirectory: true)
        AppLogger.shared.overrideLogDirectory(tempLogDir.path)
        defer { AppLogger.shared.overrideLogDirectory(previousLogDir) }

        _ = await installer.createAllLaunchDaemonServices()

        let logPath = tempLogDir.appendingPathComponent("keypath-debug.log")
        let contents = waitForLogMessage("Failed to create default user config", logURL: logPath, timeout: 3.0)
        XCTAssertNotNil(contents)
        XCTAssertTrue(contents?.contains("Failed to create default user config") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: configFile.path))
    }

    func testBundledKanataMissingProducesLogWarning() async throws {
        let missingPath = sandboxURL.appendingPathComponent("missing-kanata")
        WizardSystemPaths.setBundledKanataPathOverride(missingPath.path)
        defer { WizardSystemPaths.setBundledKanataPathOverride(nil) }
        XCTAssertEqual(WizardSystemPaths.bundledKanataPath, missingPath.path)

        let installer = LaunchDaemonInstaller()
        let previousLogDir = AppLogger.shared.currentLogDirectory()
        let logDir = homeURL
            .appendingPathComponent("Library/Logs/KeyPath", isDirectory: true)
            .appendingPathComponent("missing-kanata-\(UUID().uuidString)", isDirectory: true)
        AppLogger.shared.overrideLogDirectory(logDir.path)
        defer { AppLogger.shared.overrideLogDirectory(previousLogDir) }
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: logDir.path), withIntermediateDirectories: true)
        let logPath = logDir.appendingPathComponent("keypath-debug.log")
        try? FileManager.default.removeItem(at: logPath)

        _ = await installer.createAllLaunchDaemonServices()

        AppLogger.shared.flushBuffer()

        let contents = waitForLogMessage("Bundled Kanata binary not found", logURL: logPath)
        XCTAssertNotNil(contents)
        XCTAssertTrue(contents?.contains(missingPath.path) == true)
    }

    func testSMAppServicePendingApprovalTriggersNotification() async throws {
        let expectation = expectation(description: "SMAppService approval notification")
        let token = NotificationCenter.default.addObserver(
            forName: .smAppServiceApprovalRequired,
            object: nil,
            queue: nil
        ) { _ in expectation.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        PrivilegedOperationsCoordinator.serviceStateOverride = { .smappservicePending }
        defer { PrivilegedOperationsCoordinator.serviceStateOverride = nil }

        let result = try await PrivilegedOperationsCoordinator.shared.installServicesIfUninstalled(context: "pending-flow")
        XCTAssertFalse(result)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testInstallerFailureWhenLaunchDaemonDirectoryIsInvalid() async throws {
        let installer = LaunchDaemonInstaller()

        try FileManager.default.removeItem(at: launchDaemonsURL)
        FileManager.default.createFile(atPath: launchDaemonsURL.path, contents: Data())
        defer {
            try? FileManager.default.removeItem(atPath: launchDaemonsURL.path)
            try? FileManager.default.createDirectory(at: launchDaemonsURL, withIntermediateDirectories: true)
        }

        let result = await installer.createAllLaunchDaemonServices()
        XCTAssertFalse(result, "Installer should report failure when launch daemon directory is not usable")

        let status = await MainActor.run { installer.getServiceStatus() }
        XCTAssertFalse(status.allServicesLoaded)
    }

    func testInstallerFailureWhenLaunchDaemonsDirectoryIsReadOnly() async throws {
        let installer = LaunchDaemonInstaller()
        let originalAttributes = try FileManager.default.attributesOfItem(atPath: launchDaemonsURL.path)
        try FileManager.default.setAttributes([
            .posixPermissions: NSNumber(value: Int16(0o555))
        ], ofItemAtPath: launchDaemonsURL.path)
        defer {
            if let perms = originalAttributes[.posixPermissions] {
                try? FileManager.default.setAttributes([
                    .posixPermissions: perms
                ], ofItemAtPath: launchDaemonsURL.path)
            }
        }

        let result = await installer.createAllLaunchDaemonServices()
        XCTAssertFalse(result, "Installer should fail when LaunchDaemons dir is read-only")

        let logPath = homeURL
            .appendingPathComponent("Library/Logs/KeyPath", isDirectory: true)
            .appendingPathComponent("keypath-debug.log")
        let contents = waitForLogMessage("Failed to install plists", logURL: logPath)
        XCTAssertNotNil(contents, "Log output should exist when installation fails")
        XCTAssertTrue(contents?.contains("Failed to install plists") == true, "Log should record permission failure")
    }

    func testSMAppServiceStateReportsKanataLoadedWithoutLegacyPlist() async throws {
        smService.status = .enabled
        let installer = LaunchDaemonInstaller()

        let status = await MainActor.run { installer.getServiceStatus() }
        XCTAssertTrue(status.kanataServiceLoaded)
    }

    func testCreateKanataLaunchDaemonSkipsRegistrationWhenAlreadyManaged() async {
        smService.status = .enabled
        let installer = LaunchDaemonInstaller()

        let result = await installer.createKanataLaunchDaemon()
        XCTAssertTrue(result)
        XCTAssertEqual(smService.registerCallCount, 0)
    }

    func testCreateKanataLaunchDaemonAcknowledgesPendingApproval() async {
        smService.status = .requiresApproval
        let installer = LaunchDaemonInstaller()

        let result = await installer.createKanataLaunchDaemon()
        XCTAssertTrue(result)
        XCTAssertEqual(smService.registerCallCount, 0)
    }

    func testInstallOnlySkipsKanataWhenSMAppServiceActive() async throws {
        smService.status = .enabled
        let installer = LaunchDaemonInstaller()

        let result = await installer.createAllLaunchDaemonServicesInstallOnly()
        XCTAssertTrue(result)

        XCTAssertFalse(FileManager.default.fileExists(atPath: plistPath(for: "com.keypath.kanata")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistPath(for: "com.keypath.karabiner-vhiddaemon")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistPath(for: "com.keypath.karabiner-vhidmanager")))
    }

    func testInstallOnlyAttemptsKanataInstallWhenUninstalled() async throws {
        smService.status = .notRegistered
        let installer = LaunchDaemonInstaller()

        let result = await installer.createAllLaunchDaemonServicesInstallOnly()
        XCTAssertTrue(result)
        XCTAssertEqual(smService.registerCallCount, 1)

        for id in Self.serviceIDs.dropFirst() { // VHID services still install
            XCTAssertTrue(FileManager.default.fileExists(atPath: plistPath(for: id)), "Missing plist for \(id)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistPath(for: "com.keypath.kanata")))
    }

    func testVhidConfigurationDetection() async throws {
        let installer = LaunchDaemonInstaller()
        let installResult = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(installResult)

        XCTAssertTrue(installer.isVHIDDaemonConfiguredCorrectly())

        // Tamper with plist to break configuration
        let plistURL = launchDaemonsURL.appendingPathComponent("com.keypath.karabiner-vhiddaemon.plist")
        var dict = try plistDictionary(at: plistURL)
        dict["ProgramArguments"] = ["/tmp/bad-path"]
        (dict as NSDictionary).write(to: plistURL, atomically: true)

        XCTAssertFalse(installer.isVHIDDaemonConfiguredCorrectly())
    }

    func testKanataPlistInstalledReflectsFilesystem() async throws {
        let installer = LaunchDaemonInstaller()
        XCTAssertFalse(installer.isKanataPlistInstalled())

        let result = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(result)
        XCTAssertTrue(installer.isKanataPlistInstalled())
    }

    func testInstallOnlyLogsSkipWhenSMAppServiceActive() async throws {
        smService.status = .enabled
        let installer = LaunchDaemonInstaller()

        let logPath = homeURL
            .appendingPathComponent("Library/Logs/KeyPath", isDirectory: true)
            .appendingPathComponent("keypath-debug.log")
        try? FileManager.default.removeItem(at: logPath)

        _ = await installer.createAllLaunchDaemonServicesInstallOnly()

        let contents = waitForLogMessage("Skipping Kanata installation", logURL: logPath)
        XCTAssertNotNil(contents, "Log output should be written to disk")
        XCTAssertTrue(contents?.contains("Skipping Kanata installation") == true)
    }

    func testCreateAllServicesWritesUserConfig() async throws {
        let installer = LaunchDaemonInstaller()
        let configPath = homeURL
            .appendingPathComponent(".config/keypath", isDirectory: true)
            .appendingPathComponent("keypath.kbd")
        try? FileManager.default.removeItem(at: configPath)

        let result = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(result)

        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))
        let contents = try String(contentsOf: configPath, encoding: .utf8)
        XCTAssertTrue(contents.contains("(defcfg"))
        XCTAssertTrue(contents.contains("process-unmapped-keys"))
    }

    func testKanataPlistMigrationExpandsTildePath() async throws {
        let installer = LaunchDaemonInstaller()
        let installResult = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(installResult)

        let plistURL = launchDaemonsURL.appendingPathComponent("com.keypath.kanata.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        var dict = try plistDictionary(at: plistURL)
        if var args = dict["ProgramArguments"] as? [String], let idx = args.firstIndex(of: "--cfg"), idx + 1 < args.count {
            args[idx + 1] = "~/test/path"
            dict["ProgramArguments"] = args
            (dict as NSDictionary).write(to: plistURL, atomically: true)
        }

        let restartResult = await installer.restartUnhealthyServices()
        XCTAssertTrue(restartResult)

        let logPath = homeURL
            .appendingPathComponent("Library/Logs/KeyPath", isDirectory: true)
            .appendingPathComponent("keypath-debug.log")
        let expectedPath = NSHomeDirectory() + "/test/path"
        let logContents = waitForLogMessage("Rewriting Kanata plist config path", logURL: logPath, timeout: 2.0)
        XCTAssertNotNil(logContents, "Expected migration log entry")
        XCTAssertTrue(logContents?.contains(expectedPath) == true)
    }


    // MARK: - Helpers

    private func loadServiceContents() throws -> [String: Data] {
        var contents: [String: Data] = [:]
        for id in Self.serviceIDs {
            let path = plistPath(for: id)
            let data = try XCTUnwrap(FileManager.default.contents(atPath: path))
            contents[id] = data
        }
        return contents
    }

    private func plistPath(for serviceID: String) -> String {
        launchDaemonsURL.appendingPathComponent("\(serviceID).plist").path
    }

    private func setEnv(_ key: String, _ value: String) {
        if previousEnv[key] == nil {
            previousEnv[key] = ProcessInfo.processInfo.environment[key]
        }
        setenv(key, value, 1)
    }

    private func restoreEnv() {
        for (key, value) in previousEnv {
            if let value {
                setenv(key, value, 1)
            } else {
                _ = key.withCString { cname in
                    Darwin.unsetenv(cname)
                }
            }
        }
        previousEnv.removeAll()
    }

    private func waitForLogMessage(_ substring: String, logURL: URL, timeout: TimeInterval = 1.0) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        var latestContents: String?
        repeat {
            if let contents = try? String(contentsOf: logURL, encoding: .utf8) {
                latestContents = contents
                if contents.contains(substring) {
                    return contents
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return latestContents
    }

    private func plistDictionary(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        var format = PropertyListSerialization.PropertyListFormat.xml
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        if let dict = plist as? [String: Any] {
            return dict
        }
        if let anyHashableDict = plist as? [AnyHashable: Any] {
            var converted: [String: Any] = [:]
            for (key, value) in anyHashableDict {
                if let stringKey = key as? String {
                    converted[stringKey] = value
                }
            }
            return converted
        }
        XCTFail("Plist at \(url.path) was not a dictionary")
        return [:]
    }

    private static let serviceIDs = [
        "com.keypath.kanata",
        "com.keypath.karabiner-vhiddaemon",
        "com.keypath.karabiner-vhidmanager"
    ]

    private var installerLogPath: String {
        let dir = AppLogger.shared.currentLogDirectory()
        return (dir as NSString).appendingPathComponent("keypath-debug.log")
    }

    private func readInstallerLog() throws -> String {
        guard FileManager.default.fileExists(atPath: installerLogPath) else { return "" }
        return try String(contentsOfFile: installerLogPath, encoding: .utf8)
    }

    private func waitForLogFlush() async throws {
        try await Task.sleep(nanoseconds: 100_000_000)
    }
}

private final class TestSMAppService: SMAppServiceProtocol {
    var status: ServiceManagement.SMAppService.Status
    var registerCallCount = 0
    var unregisterCallCount = 0
    var shouldFailRegistration = false

    init(initialStatus: ServiceManagement.SMAppService.Status) {
        status = initialStatus
    }

    func register() throws {
        registerCallCount += 1
        if shouldFailRegistration {
            throw NSError(domain: "TestSMAppService", code: 1)
        }
        status = .enabled
    }

    func unregister() async throws {
        unregisterCallCount += 1
        status = .notRegistered
    }
}
