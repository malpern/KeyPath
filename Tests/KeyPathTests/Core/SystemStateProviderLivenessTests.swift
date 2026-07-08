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

    func testTCPReadinessProbeDetectsListeningAndClosedPorts() async throws {
        let listener = try LocalhostTCPListener()

        let respondingWhileListening = await SystemStateProvider.shared
            .isTCPPortResponding(port: listener.port, timeoutMs: 200)
        XCTAssertTrue(respondingWhileListening)

        listener.close()

        let respondingAfterClose = await SystemStateProvider.shared
            .isTCPPortResponding(port: listener.port, timeoutMs: 50)
        XCTAssertFalse(respondingAfterClose)
    }

    func testTCPReadinessRejectsInvalidPorts() async {
        let zeroPort = await SystemStateProvider.shared.isTCPPortResponding(port: 0, timeoutMs: 50)
        let tooLargePort = await SystemStateProvider.shared.isTCPPortResponding(port: 65536, timeoutMs: 50)
        let negativeTimeout = await SystemStateProvider.shared.isTCPPortResponding(port: 37001, timeoutMs: -1)

        XCTAssertFalse(zeroPort)
        XCTAssertFalse(tooLargePort)
        XCTAssertFalse(negativeTimeout)
    }

    func testProcessDiscoveryDelegatesToInjectedSubprocessRunner() async {
        let runner = SubprocessRunnerFake.shared
        await runner.reset()
        await runner.configurePgrepResult { pattern in
            pattern == "kanata.*--cfg" ? [1234, 5678] : []
        }
        let provider = SystemStateProvider(subprocessRunner: runner)

        let pids = await provider.processIDs(matching: "kanata.*--cfg")

        XCTAssertEqual(pids, [1234, 5678])
    }

    func testProcessDiscoveryRejectsBlankPatterns() async {
        let runner = SubprocessRunnerFake.shared
        await runner.reset()
        await runner.configurePgrepResult { _ in
            XCTFail("Blank process-discovery patterns must not invoke pgrep")
            return [9999]
        }
        let provider = SystemStateProvider(subprocessRunner: runner)

        let pids = await provider.processIDs(matching: "  \n\t  ")

        XCTAssertEqual(pids, [])
    }

    func testProcessMatchDiscoveryDelegatesToInjectedSubprocessRunner() async {
        let runner = SubprocessRunnerFake.shared
        await runner.reset()
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
        let provider = SystemStateProvider(subprocessRunner: runner)

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
        let runner = SubprocessRunnerFake.shared
        await runner.reset()
        await runner.configureRunResult { _, _ in
            XCTFail("Blank process-match patterns must not invoke pgrep")
            return ProcessResult(exitCode: 0, stdout: "", stderr: "", duration: 0.01)
        }
        let provider = SystemStateProvider(subprocessRunner: runner)

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

private final class LocalhostTCPListener {
    let port: Int
    private var fd: Int32 = -1

    init() throws {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }

        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        var bindAddr = addr
        let bindResult = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            Darwin.close(socketFD)
            throw POSIXError(code)
        }

        guard listen(socketFD, 1) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            Darwin.close(socketFD)
            throw POSIXError(code)
        }

        var boundAddr = sockaddr_in()
        var boundAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketFD, $0, &boundAddrLen)
            }
        }
        guard nameResult == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            Darwin.close(socketFD)
            throw POSIXError(code)
        }

        port = Int(UInt16(bigEndian: boundAddr.sin_port))
        fd = socketFD
    }

    deinit {
        close()
    }

    func close() {
        guard fd >= 0 else { return }
        Darwin.close(fd)
        fd = -1
    }
}
