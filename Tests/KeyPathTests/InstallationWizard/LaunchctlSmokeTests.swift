import XCTest

@testable import KeyPathAppKit

@MainActor
final class LaunchctlSmokeTests: XCTestCase {
    private var previousEnv: [String: String?] = [:]
    private var originalLaunchctlOverride: String?
    private var originalTestModeOverride: Bool?

    func testLoadServicesUsesFakeLaunchctlWhenNotInTestMode() async throws {
        let fakeLaunchctlDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        let binDir = fakeLaunchctlDir.appendingPathComponent("bin", isDirectory: true)
        let launchDaemonsDir = fakeLaunchctlDir.appendingPathComponent("Library/LaunchDaemons")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: launchDaemonsDir, withIntermediateDirectories: true)

        let logURL = fakeLaunchctlDir.appendingPathComponent("launchctl.log")
        // Create the log file so it exists even if the script doesn't run
        FileManager.default.createFile(atPath: logURL.path, contents: Data())

        let scriptURL = binDir.appendingPathComponent("launchctl")
        let script = #"""
        #!/bin/bash
        printf "%s\n" "$*" >> "\#(logURL.path)"
        exit 0
        """#
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        // Create a minimal test plist for launchctl to load
        let testPlistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.keypath.kanata</string>
        </dict>
        </plist>
        """
        let testPlistPath = launchDaemonsDir.appendingPathComponent("com.keypath.kanata.plist")
        try testPlistContent.write(to: testPlistPath, atomically: true, encoding: .utf8)

        // Set up test environment (main-actor isolated)
        await MainActor.run {
            previousEnv.removeAll()
            originalLaunchctlOverride = LaunchDaemonInstaller.launchctlPathOverride
            originalTestModeOverride = LaunchDaemonInstaller.isTestModeOverride
            LaunchDaemonInstaller.launchctlPathOverride = scriptURL.path
            LaunchDaemonInstaller.isTestModeOverride = false // Disable test mode to force real launchctl execution
            setEnv("KEYPATH_TEST_ROOT", fakeLaunchctlDir.path)
            setEnv("KEYPATH_LAUNCH_DAEMONS_DIR", launchDaemonsDir.path)
        }

        let installer = LaunchDaemonInstaller()
        let success = await installer.loadServices()

        XCTAssertTrue(success, "Load services should succeed using the fake launchctl")
        let log = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(log.contains("load"), "Fake launchctl should have recorded load commands")
        await MainActor.run {
            if let original = originalLaunchctlOverride {
                LaunchDaemonInstaller.launchctlPathOverride = original
            } else {
                LaunchDaemonInstaller.launchctlPathOverride = nil
            }
            LaunchDaemonInstaller.isTestModeOverride = originalTestModeOverride
            restoreEnv()
        }
    }

    @MainActor private func setEnv(_ key: String, _ value: String) {
        if previousEnv[key] == nil {
            previousEnv[key] = ProcessInfo.processInfo.environment[key]
        }
        setenv(key, value, 1)
    }

    @MainActor private func restoreEnv() {
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
