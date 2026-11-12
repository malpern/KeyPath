@testable import KeyPathAppKit
import XCTest

final class ExternalKanataServiceCommandTests: XCTestCase {
    /// A child that fills both pipe buffers (64 KB each) before exiting used to
    /// deadlock: the caller waited for exit before reading either pipe.
    func testCommandWithLargeOutputOnBothStreamsDoesNotHang() async throws {
        let script = "head -c 300000 /dev/zero | tr '\\\\0' o; head -c 300000 /dev/zero | tr '\\\\0' e >&2; exit 3"
        let result = try await ExternalKanataService.runCommand("/bin/sh", arguments: ["-c", script])
        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(result.stdout.count, 300_000)
        XCTAssertEqual(result.stderr.count, 300_000)
    }

    func testKillProcessStopsALiveProcess() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }

        try await ExternalKanataService.killProcess(pid: Int(child.processIdentifier))
        child.waitUntilExit()

        XCTAssertFalse(child.isRunning)
        XCTAssertEqual(child.terminationReason, .uncaughtSignal)
    }

    func testKillProcessTreatsAMissingProcessAsStopped() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run()
        child.waitUntilExit()

        try await ExternalKanataService.killProcess(pid: Int(child.processIdentifier))
    }

    /// `/bin/kill` exits 1 for both "no such process" and "permission denied",
    /// and the old code read exit 1 as "already gone": stopping a root-owned
    /// Kanata reported success while it kept running.
    func testKillProcessReportsPermissionDenied() async {
        do {
            try await ExternalKanataService.killProcess(pid: 1) // launchd, owned by root
            XCTFail("Signalling a process we do not own must fail")
        } catch {
            XCTAssertEqual((error as NSError).code, Int(EPERM))
        }
    }
}
