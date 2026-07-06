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
}
