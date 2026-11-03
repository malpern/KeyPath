import Darwin
import Foundation
@testable import KeyPathAppKit
import XCTest

final class SessionWorkerSweepTests: XCTestCase {
    private static let trashedExecutable = "/Users/someone/.Trash/KeyPath.app/Contents/MacOS/KeyPath"

    // MARK: - Recognizing workers

    /// The 2026-11-03 orphans: capability probes from a trashed bundle whose owner had exited.
    func testParsesAnOrphanedProbeFromATrashedBundle() {
        let worker = SessionWorkerProcess.parse(pid: 13284, arguments: [
            Self.trashedExecutable, "--session-capabilities", "--session-report", "/tmp/r.json",
            "--session-nonce", UUID().uuidString, "--session-owner", "30378", "--session-port", "37001",
            "--session-config", "/Users/someone/.config/keypath/keypath.kbd",
        ])
        XCTAssertEqual(worker, SessionWorkerProcess(pid: 13284, mode: .capabilities, ownerPID: 30378))
    }

    func testParsesARuntimeWorker() {
        let worker = SessionWorkerProcess.parse(pid: 42, arguments: [
            "/Applications/KeyPath.app/Contents/MacOS/KeyPath", "--session-runtime", "--session-owner", "41",
        ])
        XCTAssertEqual(worker, SessionWorkerProcess(pid: 42, mode: .runtime, ownerPID: 41))
    }

    func testIgnoresTheAppItselfAndOtherProcesses() {
        XCTAssertNil(SessionWorkerProcess.parse(pid: 1, arguments: ["/Applications/KeyPath.app/Contents/MacOS/KeyPath"]))
        XCTAssertNil(SessionWorkerProcess.parse(pid: 2, arguments: ["/usr/bin/grep", "--session-runtime"]))
        XCTAssertNil(SessionWorkerProcess.parse(pid: 3, arguments: [
            "/Applications/KeyPath.app/Contents/MacOS/keypath-cli", "--session-runtime",
        ]))
        XCTAssertNil(SessionWorkerProcess.parse(pid: 4, arguments: []))
    }

    func testMissingOwnerValueParsesWithoutOwner() {
        let worker = SessionWorkerProcess.parse(pid: 5, arguments: [Self.trashedExecutable, "--session-runtime", "--session-owner"])
        XCTAssertEqual(worker, SessionWorkerProcess(pid: 5, mode: .runtime, ownerPID: nil))
    }

    func testParsesKernelArgumentLayout() {
        var bytes = withUnsafeBytes(of: Int32(3)) { Array($0) }
        for string in [Self.trashedExecutable, "", "", "KeyPath", "--session-capabilities", "--session-owner"] {
            bytes += Array(string.utf8) + [0]
        }
        bytes += Array("KEYPATH=1".utf8) + [0]
        XCTAssertEqual(SessionWorkerSweep.parseProcArgs(bytes),
                       [Self.trashedExecutable, "--session-capabilities", "--session-owner"])
        XCTAssertNil(SessionWorkerSweep.parseProcArgs([1, 0]))
    }

    // MARK: - Stopping workers

    private final class FakeProcesses: @unchecked Sendable {
        private let lock = NSLock()
        private var running: [SessionWorkerProcess]
        /// Workers that exit on SIGTERM; others ignore it.
        private let exitOnTerm: Set<pid_t>
        private(set) var signals: [(pid_t, Int32)] = []

        init(_ running: [SessionWorkerProcess], exitOnTerm: Set<pid_t>) {
            self.running = running
            self.exitOnTerm = exitOnTerm
        }

        var sweep: SessionWorkerSweep {
            SessionWorkerSweep(
                list: { self.locked { self.running } },
                signal: { pid, number in
                    self.locked {
                        self.signals.append((pid, number))
                        if number == SIGKILL || self.exitOnTerm.contains(pid) { self.running.removeAll { $0.pid == pid } }
                    }
                },
                sleep: { _ in }
            )
        }

        func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
        func received(_ number: Int32) -> [pid_t] { locked { signals.filter { $0.1 == number }.map(\.0) } }
    }

    func testNoWorkersSucceedsWithoutSignalling() async {
        let fake = FakeProcesses([], exitOnTerm: [])
        let outcome = await fake.sweep.stopAll()
        XCTAssertTrue(outcome.succeeded)
        XCTAssertTrue(fake.signals.isEmpty)
    }

    /// Every worker is stopped, not only the one the live app tracks.
    func testStopsEveryWorkerIncludingOrphans() async {
        let tracked = SessionWorkerProcess(pid: 100, mode: .runtime, ownerPID: 99)
        let orphanA = SessionWorkerProcess(pid: 13284, mode: .capabilities, ownerPID: 30378)
        let orphanB = SessionWorkerProcess(pid: 29722, mode: .capabilities, ownerPID: 30378)
        let fake = FakeProcesses([tracked, orphanA, orphanB], exitOnTerm: [100, 13284, 29722])
        let outcome = await fake.sweep.stopAll()
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(Set(fake.received(SIGTERM)), [100, 13284, 29722])
        XCTAssertTrue(fake.received(SIGKILL).isEmpty)
    }

    func testKillsAWedgedProbeAfterItsGrace() async {
        let probe = SessionWorkerProcess(pid: 13284, mode: .capabilities, ownerPID: 30378)
        let fake = FakeProcesses([probe], exitOnTerm: [])
        let outcome = await fake.sweep.stopAll(probeGrace: .milliseconds(200), runtimeGrace: .seconds(1),
                                               poll: .milliseconds(100))
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(fake.received(SIGKILL), [13284])
    }

    /// A runtime worker may hold a Caps mapping; it is never killed, and a
    /// worker that ignores SIGTERM is reported, not hidden.
    func testNeverKillsARuntimeWorkerAndReportsItRemaining() async {
        let runtime = SessionWorkerProcess(pid: 100, mode: .runtime, ownerPID: 99)
        let fake = FakeProcesses([runtime], exitOnTerm: [])
        let outcome = await fake.sweep.stopAll(probeGrace: .milliseconds(100), runtimeGrace: .milliseconds(500),
                                               poll: .milliseconds(100))
        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.remaining, [runtime])
        XCTAssertTrue(fake.received(SIGKILL).isEmpty)
    }

    /// Reads the real process table without signalling anything: this test
    /// process is not a KeyPath worker, so it must never list itself.
    func testLiveListingNeverIncludesThisProcess() {
        XCTAssertFalse(SessionWorkerSweep.currentUserSessionWorkers().contains { $0.pid == getpid() })
        XCTAssertNotNil(SessionWorkerSweep.arguments(of: getpid()))
    }
}
