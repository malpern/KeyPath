import XCTest

@testable import KeyPath

@MainActor
final class LaunchctlSmokeTests: XCTestCase {
    private var previousEnv: [String: String?] = [:]
    private var originalLaunchctlOverride: String?

    override func setUp() {
        super.setUp()
        previousEnv.removeAll()
        originalLaunchctlOverride = LaunchDaemonInstaller.launchctlPathOverride
    }

    override func tearDown() {
        if let original = originalLaunchctlOverride {
            LaunchDaemonInstaller.launchctlPathOverride = original
        } else {
            LaunchDaemonInstaller.launchctlPathOverride = nil
        }
        restoreEnv()
        super.tearDown()
    }

    func testLoadServicesUsesFakeLaunchctlWhenNotInTestMode() async throws {
        let fakeLaunchctlDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let binDir = fakeLaunchctlDir.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        let logURL = fakeLaunchctlDir.appendingPathComponent("launchctl.log")
        let scriptURL = binDir.appendingPathComponent("launchctl")
        let script = #"""
            #!/bin/bash
            echo "$@" >> "\(logURL.path)"
            exit 0
            """#
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        LaunchDaemonInstaller.launchctlPathOverride = scriptURL.path
        setEnv("KEYPATH_TEST_MODE", "0")
        setEnv("KEYPATH_TEST_ROOT", fakeLaunchctlDir.path)
        setEnv("KEYPATH_LAUNCH_DAEMONS_DIR", fakeLaunchctlDir.appendingPathComponent("Library/LaunchDaemons").path)

        let installer = LaunchDaemonInstaller()
        _ = await installer.createAllLaunchDaemonServicesInstallOnly()
        let success = await installer.loadServices()

        XCTAssertTrue(success, "Load services should succeed using the fake launchctl")
        let log = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(log.contains("load"), "Fake launchctl should have recorded load commands")
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
}
