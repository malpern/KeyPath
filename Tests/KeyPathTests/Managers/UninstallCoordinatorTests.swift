import XCTest
@testable import KeyPath

@MainActor
final class UninstallCoordinatorTests: XCTestCase {
    func testUninstallRemovesPathsAndLogsSuccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("keypath-uninstall-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let launchDaemons = root.appendingPathComponent("Library/LaunchDaemons", isDirectory: true)
        try FileManager.default.createDirectory(at: launchDaemons, withIntermediateDirectories: true)
        let vhid = launchDaemons.appendingPathComponent("com.keypath.kanata.plist")
        FileManager.default.createFile(atPath: vhid.path, contents: Data())
        let helperTools = root.appendingPathComponent("Library/PrivilegedHelperTools", isDirectory: true)
        try FileManager.default.createDirectory(at: helperTools, withIntermediateDirectories: true)
        let app = root.appendingPathComponent("Applications/KeyPath.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)

        let scriptURL = root.appendingPathComponent("fake-uninstall.sh")
        try #"""
        #!/bin/bash
        set -e
        ROOT="${TEST_UNINSTALL_ROOT:?}"
        rm -rf "$ROOT/Library/LaunchDaemons"
        rm -rf "$ROOT/Library/PrivilegedHelperTools"
        rm -rf "$ROOT/Applications" 2>/dev/null || true
        echo "removed" > "$ROOT/cleanup.txt"
        """#.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let coordinator = UninstallCoordinator(
            resolveUninstallerURL: { scriptURL },
            runWithAdminPrivileges: { url in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [url.path]
                process.environment = ["TEST_UNINSTALL_ROOT": root.path]
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do {
                    try process.run()
                    process.waitUntilExit()
                    let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let error = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    return AppleScriptResult(success: process.terminationStatus == 0, output: output, error: error, exitStatus: process.terminationStatus)
                } catch {
                    return AppleScriptResult(success: false, output: "", error: error.localizedDescription, exitStatus: -1)
                }
            }
        )
        let success = await coordinator.uninstall()

        XCTAssertTrue(success)
        XCTAssertTrue(coordinator.didSucceed)
        XCTAssertNil(coordinator.lastError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: launchDaemons.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: helperTools.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("cleanup.txt").path))
        XCTAssertTrue(coordinator.logLines.contains { $0.contains("Uninstall completed") })
    }

    func testUninstallFailsWhenScriptMissing() async throws {
        let coordinator = UninstallCoordinator(
            resolveUninstallerURL: { nil },
            runWithAdminPrivileges: { _ in AppleScriptResult(success: false, output: "", error: "", exitStatus: -1) }
        )

        let success = await coordinator.uninstall()

        XCTAssertFalse(success)
        XCTAssertFalse(coordinator.didSucceed)
        XCTAssertEqual(coordinator.lastError, "Uninstaller script wasn't found in this build.")
        XCTAssertTrue(coordinator.logLines.contains { $0.contains("Uninstaller script wasn't found") })
    }

    func testUninstallLogsAdminError() async throws {
        let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-fail.sh")
        let coordinator = UninstallCoordinator(
            resolveUninstallerURL: { errorURL },
            runWithAdminPrivileges: { _ in AppleScriptResult(success: false, output: "", error: "Permission denied", exitStatus: 1) }
        )

        let success = await coordinator.uninstall()

        XCTAssertFalse(success)
        XCTAssertFalse(coordinator.didSucceed)
        XCTAssertEqual(coordinator.lastError, "Permission denied")
        XCTAssertTrue(coordinator.logLines.contains { $0.contains("Permission denied") })
    }

    func testUninstallLogsExitCodeWhenAdminErrorMissingMessage() async throws {
        let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-fail.sh")
        let coordinator = UninstallCoordinator(
            resolveUninstallerURL: { errorURL },
            runWithAdminPrivileges: { _ in AppleScriptResult(success: false, output: "", error: "", exitStatus: 42) }
        )

        let success = await coordinator.uninstall()

        XCTAssertFalse(success)
        XCTAssertFalse(coordinator.didSucceed)
        XCTAssertEqual(coordinator.lastError, "Uninstall failed with exit code 42")
        XCTAssertTrue(coordinator.logLines.contains { $0.contains("Uninstall failed (error code 42)") })
    }
}
