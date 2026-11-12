import Darwin
import Foundation
@testable import KeyPathCore
@preconcurrency import XCTest

final class SystemStateProviderLivenessTests: XCTestCase {
    func testProcessLivenessProbeTreatsCurrentProcessAsAliveAndExitedProcessAsDead() throws {
        XCTAssertTrue(SystemStateProvider.isProcessAlive(pid: getpid()))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exit 0"]

        try process.run()
        let childPID = pid_t(process.processIdentifier)
        process.waitUntilExit()

        XCTAssertFalse(SystemStateProvider.isProcessAlive(pid: childPID))
    }

    func testKanataReadinessRequiresRunningAndResponding() {
        XCTAssertTrue(KanataLivenessEvidence(pid: getpid(), running: true, responding: true).ready)
        XCTAssertFalse(KanataLivenessEvidence(pid: getpid(), running: true, responding: false).ready)
        XCTAssertFalse(KanataLivenessEvidence(pid: nil, running: false, responding: true).ready)
        XCTAssertFalse(KanataLivenessEvidence(pid: nil, running: false, responding: false).ready)
    }

    func testProcessLivenessRejectsNonPositivePIDs() {
        XCTAssertFalse(SystemStateProvider.isProcessAlive(pid: 0))
        XCTAssertFalse(SystemStateProvider.isProcessAlive(pid: -1))
    }

    func testProcessDiscoveryDelegatesToInjectedSubprocessRunner() async {
        let runner = SubprocessRunnerFake()
        await runner.configurePgrepResult { pattern in
            pattern == "kanata.*--cfg" ? [1234, 5678] : []
        }
        let provider = SystemStateProvider(probes: runner.systemProbeClient())

        let pids = await provider.processIDs(matching: "kanata.*--cfg")

        XCTAssertEqual(pids, [1234, 5678])
    }

    func testProcessDiscoveryRejectsBlankPatterns() async {
        let runner = SubprocessRunnerFake()
        await runner.configurePgrepResult { _ in
            XCTFail("Blank process-discovery patterns must not invoke pgrep")
            return [9999]
        }
        let provider = SystemStateProvider(probes: runner.systemProbeClient())

        let pids = await provider.processIDs(matching: "  \n\t  ")

        XCTAssertEqual(pids, [])
    }

    func testProcessMatchDiscoveryDelegatesToInjectedSubprocessRunner() async {
        let runner = SubprocessRunnerFake()
        await runner.configureRunResult { executable, args in
            if executable == "/usr/bin/pgrep", args == ["-fl", "kanata"] {
                return ProcessResult(
                    exitCode: 0,
                    stdout: """
                    123 kanata --cfg /Users/example/.config/keypath/keypath.kbd
                    invalid
                    456 /opt/homebrew/bin/kanata --cfg /tmp/other.kbd

                    """,
                    stderr: "",
                    duration: 0.01
                )
            }
            return ProcessResult(exitCode: 1, stdout: "", stderr: "", duration: 0.01)
        }
        let provider = SystemStateProvider(probes: runner.systemProbeClient())

        let matches = await provider.processMatches(matching: "kanata")
        let commands = await runner.executedCommands

        XCTAssertEqual(
            matches,
            [
                SystemProcessMatch(pid: 123, command: "kanata --cfg /Users/example/.config/keypath/keypath.kbd"),
                SystemProcessMatch(pid: 456, command: "/opt/homebrew/bin/kanata --cfg /tmp/other.kbd")
            ]
        )
        XCTAssertTrue(
            commands.contains { $0.executable == "/usr/bin/pgrep" && $0.args == ["-fl", "kanata"] },
            "SystemStateProvider should own pgrep -fl process-match discovery"
        )
    }

    func testProcessMatchDiscoveryRejectsBlankPatterns() async {
        let runner = SubprocessRunnerFake()
        await runner.configureRunResult { _, _ in
            XCTFail("Blank process-match patterns must not invoke pgrep")
            return ProcessResult(exitCode: 0, stdout: "", stderr: "", duration: 0.01)
        }
        let provider = SystemStateProvider(probes: runner.systemProbeClient())

        let matches = await provider.processMatches(matching: "  \n\t  ")

        XCTAssertEqual(matches, [])
    }

    func testSynchronousProcessDiscoveryRejectsBlankPatterns() {
        let pids = SystemStateProvider.processIDsSynchronously(matching: "  \n\t  ")

        XCTAssertEqual(pids, [])
    }

    func testSynchronousProcessDiscoveryReturnsEmptyForMissingProcess() {
        let pids = SystemStateProvider.processIDsSynchronously(
            matching: "keypath_missing_process_pattern_7B3C9991_2A59_4F3E_AA43"
        )

        XCTAssertEqual(pids, [])
    }
}
