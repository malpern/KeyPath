import Foundation
@testable import KeyPathCore
import XCTest

/// Tests for PrivilegedCommandRunner.Batch script generation, including the
/// kp_timeout watchdog added for #927 (privileged scripts hanging forever on
/// `launchctl kickstart -k` of an unrunnable service).
final class PrivilegedCommandRunnerBatchTests: XCTestCase {
    func testEmptyBatchProducesNoOpScript() {
        let batch = PrivilegedCommandRunner.Batch(label: "empty", commands: [])
        XCTAssertEqual(batch.script, ":")

        let whitespaceOnly = PrivilegedCommandRunner.Batch(label: "blank", commands: ["  ", "\n"])
        XCTAssertEqual(whitespaceOnly.script, ":")
    }

    func testScriptContainsPreludeAndCommandsInOrder() {
        let batch = PrivilegedCommandRunner.Batch(
            label: "repair",
            commands: ["/bin/echo one", "kp_timeout 15 /bin/launchctl kickstart -k system/foo"]
        )
        let script = batch.script

        XCTAssertTrue(script.hasPrefix(PrivilegedCommandRunner.Batch.scriptPrelude))
        XCTAssertTrue(script.contains("set -e"))
        XCTAssertTrue(script.contains("kp_timeout() {"))

        let echoIndex = script.range(of: "/bin/echo one")!.lowerBound
        let kickstartIndex = script.range(of: "kickstart -k system/foo")!.lowerBound
        XCTAssertLessThan(echoIndex, kickstartIndex)
    }

    func testDefaultPromptDerivedFromLabel() {
        let batch = PrivilegedCommandRunner.Batch(label: "Repair VirtualHID Services", commands: [":"])
        XCTAssertEqual(batch.prompt, "KeyPath needs to repair virtualhid services.")
    }

    /// kp_timeout must kill a hung command and propagate a nonzero status,
    /// while leaving fast commands untouched.
    func testKpTimeoutKillsHungCommandAndPreservesExitCodes() throws {
        // Success passes through
        try assertScript(
            commands: ["kp_timeout 5 /bin/echo ok"],
            expectedStatus: 0, within: 3
        )
        // Failure status propagates (set -e aborts the script → nonzero)
        try assertScript(
            commands: ["kp_timeout 5 /usr/bin/false"],
            expectedStatusNot: 0, within: 3
        )
        // A hung command is killed at the deadline instead of blocking forever.
        // Fractional sleep keeps the wall-clock cost minimal (CLAUDE.md: no real
        // sleeps in tests — a wall-clock watchdog needs SOME clock; keep it tiny).
        let start = Date()
        try assertScript(
            commands: ["kp_timeout 0.3 /bin/sleep 30"],
            expectedStatusNot: 0, within: 3
        )
        XCTAssertLessThan(Date().timeIntervalSince(start), 3, "watchdog did not fire in time")
    }

    private func assertScript(
        commands: [String],
        expectedStatus: Int32? = nil,
        expectedStatusNot: Int32? = nil,
        within seconds: TimeInterval
    ) throws {
        let batch = PrivilegedCommandRunner.Batch(label: "test", commands: commands)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", batch.script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let exited = expectation(description: "script exits: \(commands)")
        process.terminationHandler = { _ in exited.fulfill() }
        try process.run()
        wait(for: [exited], timeout: seconds)

        if process.isRunning {
            process.terminate()
            XCTFail("script did not finish within \(seconds)s: \(commands)")
            return
        }
        if let expectedStatus {
            XCTAssertEqual(process.terminationStatus, expectedStatus, "commands: \(commands)")
        }
        if let expectedStatusNot {
            XCTAssertNotEqual(process.terminationStatus, expectedStatusNot, "commands: \(commands)")
        }
    }
}
