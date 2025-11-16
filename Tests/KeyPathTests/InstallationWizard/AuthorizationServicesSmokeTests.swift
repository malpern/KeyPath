import Darwin
import ServiceManagement
import XCTest

@testable import KeyPath
import KeyPathCore

@MainActor
final class AuthorizationServicesSmokeTests: XCTestCase {
    private var sandboxURL: URL!
    private var launchDaemonsURL: URL!
    private var homeURL: URL!
    private var previousEnv: [String: String?] = [:]
    private var originalRunner: ((String) -> Bool)?
    private var originalSMFactory: ((String) -> SMAppServiceProtocol)!
    private var smService: TestSMAppService!
    private var bundledKanataURL: URL!
    private var stubBinURL: URL!
    private var launchctlLogURL: URL!
    private var originalAllowAdminOps: Bool = false

    override func setUp() async throws {
        try await super.setUp()
        originalAllowAdminOps = TestEnvironment.allowAdminOperationsInTests
        TestEnvironment.allowAdminOperationsInTests = true

        sandboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("auth-smoke-\(UUID().uuidString)", isDirectory: true)
        launchDaemonsURL = sandboxURL.appendingPathComponent("Library/LaunchDaemons", isDirectory: true)
        homeURL = sandboxURL
            .appendingPathComponent("Users", isDirectory: true)
            .appendingPathComponent(NSUserName(), isDirectory: true)

        try FileManager.default.createDirectory(at: launchDaemonsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        let logsURL = homeURL.appendingPathComponent("Library/Logs/KeyPath", isDirectory: true)
        try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)

        setEnv("KEYPATH_TEST_ROOT", sandboxURL.path)
        setEnv("KEYPATH_LAUNCH_DAEMONS_DIR", launchDaemonsURL.path)
        setEnv("KEYPATH_TEST_MODE", "1")  // Fixed: was "0" which disabled test mode
        setEnv("HOME", homeURL.path)
        setEnv("KEYPATH_HOME_DIR_OVERRIDE", homeURL.path)
        setEnv("KEYPATH_LOG_DIR_OVERRIDE", logsURL.path)

        bundledKanataURL = sandboxURL.appendingPathComponent("bundled-kanata")
        FileManager.default.createFile(atPath: bundledKanataURL.path, contents: Data("kanata".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledKanataURL.path)
        WizardSystemPaths.setBundledKanataPathOverride(bundledKanataURL.path)

        stubBinURL = sandboxURL.appendingPathComponent("fake-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: stubBinURL, withIntermediateDirectories: true)
        launchctlLogURL = sandboxURL.appendingPathComponent("launchctl.log")
        FileManager.default.createFile(atPath: launchctlLogURL.path, contents: nil)
        createStub(name: "launchctl", contents: """
        #!/bin/bash
        if [[ -n "$FAKE_LAUNCHCTL_LOG" ]]; then
          if [[ $# -gt 0 ]]; then
            printf "%s" "$1" >> "$FAKE_LAUNCHCTL_LOG"
            shift
            for arg in "$@"; do
              printf " %s" "$arg" >> "$FAKE_LAUNCHCTL_LOG"
            done
          fi
          printf "\\n" >> "$FAKE_LAUNCHCTL_LOG"
        fi
        exit 0
        """)
        createStub(name: "chown", contents: """
        #!/bin/bash
        exit 0
        """)

        let originalPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setEnv("PATH", "\(stubBinURL.path):\(originalPath)")

        originalRunner = LaunchDaemonInstaller.authorizationScriptRunnerOverride
        LaunchDaemonInstaller.authorizationScriptRunnerOverride = { [weak self] scriptPath in
            guard let self else { return false }
            return self.runAuthorizationScript(at: scriptPath)
        }

        originalSMFactory = KanataDaemonManager.smServiceFactory
        smService = TestSMAppService(initialStatus: .notRegistered)
        KanataDaemonManager.smServiceFactory = { _ in self.smService }
    }

    override func tearDown() async throws {
        LaunchDaemonInstaller.authorizationScriptRunnerOverride = originalRunner
        KanataDaemonManager.smServiceFactory = originalSMFactory
        WizardSystemPaths.setBundledKanataPathOverride(nil)
        TestEnvironment.allowAdminOperationsInTests = originalAllowAdminOps
        restoreEnv()
        if let sandboxURL, FileManager.default.fileExists(atPath: sandboxURL.path) {
            try? FileManager.default.removeItem(at: sandboxURL)
        }
        sandboxURL = nil
        try await super.tearDown()
    }

    func testAuthorizationServicesInstallationCreatesPlistsAndBootstraps() async throws {
        let installer = LaunchDaemonInstaller()

        let success = await installer.createAllLaunchDaemonServices()
        XCTAssertTrue(success)

        for id in ["com.keypath.kanata", "com.keypath.karabiner-vhiddaemon", "com.keypath.karabiner-vhidmanager"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: plistPath(for: id)),
                          "Expected plist for \(id)")
        }

        let logContents = try String(contentsOf: launchctlLogURL, encoding: .utf8)
        XCTAssertTrue(logContents.contains("bootstrap system \(plistPath(for: "com.keypath.karabiner-vhiddaemon"))"))
        XCTAssertTrue(logContents.contains("bootstrap system \(plistPath(for: "com.keypath.karabiner-vhidmanager"))"))
        XCTAssertTrue(logContents.contains("bootstrap system \(plistPath(for: "com.keypath.kanata"))"))

        if let report = installer.lastInstallerReport {
            XCTAssertTrue(report.success)
            XCTAssertNil(report.failureReason)
        } else {
            XCTFail("Expected installer report")
        }
    }

    // MARK: - Helpers

    private func runAuthorizationScript(at path: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [path]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(stubBinURL.path):\(environment["PATH"] ?? "")"
        environment["FAKE_LAUNCHCTL_LOG"] = launchctlLogURL.path
        task.environment = environment
        let output = Pipe()
        task.standardOutput = output
        task.standardError = output
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func createStub(name: String, contents: String) {
        let url = stubBinURL.appendingPathComponent(name)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
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
                Darwin.unsetenv(key)
            }
        }
        previousEnv.removeAll()
    }
}

private final class TestSMAppService: SMAppServiceProtocol {
    var status: ServiceManagement.SMAppService.Status
    var registerCallCount = 0
    var unregisterCallCount = 0

    init(initialStatus: ServiceManagement.SMAppService.Status) {
        status = initialStatus
    }

    func register() throws {
        registerCallCount += 1
        status = .enabled
    }

    func unregister() async throws {
        unregisterCallCount += 1
        status = .notRegistered
    }
}
