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
        XCTAssertEqual(worker, SessionWorkerProcess(pid: 13284, mode: .capabilities, ownerPID: 30378, executable: Self.trashedExecutable))
    }

    func testParsesARuntimeWorker() {
        let worker = SessionWorkerProcess.parse(pid: 42, arguments: [
            "/Applications/KeyPath.app/Contents/MacOS/KeyPath", "--session-runtime", "--session-owner", "41",
        ])
        XCTAssertEqual(worker?.mode, .runtime)
        XCTAssertEqual(worker?.ownerPID, 41)
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
        XCTAssertEqual(worker?.mode, .runtime)
        XCTAssertNil(worker?.ownerPID)
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

        /// Each sleep advances a fake clock, so graces are wall-clock bounded.
        let clock = Locked(0.0)
        var arrivals: [Int: SessionWorkerProcess] = [:]
        private var polls = 0

        var sweep: SessionWorkerSweep {
            SessionWorkerSweep(
                list: { self.locked {
                    if let late = self.arrivals[self.polls] { self.running.append(late) }
                    self.polls += 1
                    return Optional(self.running)
                } },
                signal: { pid, number in
                    self.locked {
                        self.signals.append((pid, number))
                        if number == SIGKILL || self.exitOnTerm.contains(pid) { self.running.removeAll { $0.pid == pid } }
                    }
                },
                sleep: { duration in
                    self.clock.update { $0 += Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18 }
                },
                uptime: { self.clock.value }
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
        let outcome = await fake.sweep.stopAll(probeGrace: 0.2, runtimeGrace: 1, poll: .milliseconds(100))
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(fake.received(SIGKILL), [13284])
    }

    /// A runtime worker may hold a Caps mapping; it is never killed, and a
    /// worker that ignores SIGTERM is reported, not hidden.
    func testNeverKillsARuntimeWorkerAndReportsItRemaining() async {
        let runtime = SessionWorkerProcess(pid: 100, mode: .runtime, ownerPID: 99)
        let fake = FakeProcesses([runtime], exitOnTerm: [])
        let outcome = await fake.sweep.stopAll(probeGrace: 0.1, runtimeGrace: 0.5, poll: .milliseconds(100))
        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.remaining, [runtime])
        XCTAssertTrue(fake.received(SIGKILL).isEmpty)
    }

    /// A worker that appears after the first listing is signalled, and a late
    /// probe is still killed once the probe grace has passed.
    func testSignalsWorkersThatAppearMidSweep() async {
        let first = SessionWorkerProcess(pid: 100, mode: .runtime, ownerPID: 99)
        let late = SessionWorkerProcess(pid: 200, mode: .capabilities, ownerPID: 99)
        let fake = FakeProcesses([first], exitOnTerm: [100])
        // Listed on the first poll, after the initial SIGTERM went out.
        fake.arrivals[1] = late
        let outcome = await fake.sweep.stopAll(probeGrace: 0.2, runtimeGrace: 2, poll: .milliseconds(100))
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(Set(fake.received(SIGTERM)), [100, 200])
        XCTAssertEqual(fake.received(SIGKILL), [200])
        XCTAssertEqual(Set(outcome.found.map(\.pid)), [100, 200])
    }

    func testUninstallScopeIsTheRemovedBundleAndOrphans() {
        let app = URL(fileURLWithPath: "/Applications/KeyPath.app")
        let dev = "/Users/me/dev/KeyPath.app/Contents/MacOS/KeyPath"
        let own = SessionWorkerProcess(pid: 1, mode: .runtime, ownerPID: 10,
                                       executable: "/Applications/KeyPath.app/Contents/MacOS/KeyPath")
        let otherLive = SessionWorkerProcess(pid: 2, mode: .runtime, ownerPID: 20, executable: dev)
        let orphan = SessionWorkerProcess(pid: 3, mode: .capabilities, ownerPID: 30378,
                                          executable: Self.trashedExecutable)
        let ownerless = SessionWorkerProcess(pid: 4, mode: .capabilities, ownerPID: nil,
                                             executable: Self.trashedExecutable)
        let apps: [pid_t: String] = [10: "/Applications/KeyPath.app/Contents/MacOS/KeyPath", 20: dev]
        XCTAssertTrue(own.belongsToUninstall(of: app) { apps[$0] })
        XCTAssertFalse(otherLive.belongsToUninstall(of: app) { apps[$0] })
        XCTAssertTrue(orphan.belongsToUninstall(of: app) { apps[$0] })
        XCTAssertTrue(ownerless.belongsToUninstall(of: app) { apps[$0] })
        // A sibling bundle whose name starts with the removed one is not inside it.
        let sibling = SessionWorkerProcess(pid: 5, mode: .runtime, ownerPID: 20,
                                           executable: "/Applications/KeyPath.app.old/Contents/MacOS/KeyPath")
        XCTAssertTrue(sibling.belongsToUninstall(of: app) { apps[$0] }, "Owner 20 runs a different bundle")
    }

    /// The 2026-11-03 orphans outlived their owner by hours. A reused owner
    /// PID now belonging to an unrelated process, or to another KeyPath
    /// bundle, does not make the orphan look owned.
    func testReusedOwnerPIDDoesNotHideAnOrphan() {
        let app = URL(fileURLWithPath: "/Applications/KeyPath.app")
        let orphan = SessionWorkerProcess(pid: 13284, mode: .runtime, ownerPID: 30378,
                                          executable: Self.trashedExecutable)
        // PID 30378 is now some non-KeyPath process: not in the app table at all.
        XCTAssertTrue(orphan.belongsToUninstall(of: app) { _ in nil })
        // PID 30378 is now a KeyPath app from a different bundle.
        XCTAssertTrue(orphan.belongsToUninstall(of: app) { _ in "/Users/me/dev/KeyPath.app/Contents/MacOS/KeyPath" })
    }

    /// The parser recognizes exactly the argv the app launches workers with.
    func testParsesTheRealLaunchArguments() {
        for probe in [true, false] {
            let arguments = ServiceLifecycleCoordinator.sessionLaunchArguments(
                capabilitiesOnly: probe, reportPath: "/tmp/r/report.json", nonce: UUID().uuidString,
                ownerPID: 30378, port: 37001, configPath: "/Users/me/.config/keypath/keypath.kbd"
            )
            let worker = SessionWorkerProcess.parse(pid: 1, arguments: [Self.trashedExecutable] + arguments)
            XCTAssertEqual(worker?.mode, probe ? .capabilities : .runtime)
            XCTAssertEqual(worker?.ownerPID, 30378)
        }
    }

    /// One unreadable listing is retried; a process exiting mid-read must not
    /// make the whole sweep unverified.
    func testSingleUnreadableListingIsRetried() async {
        let reads = Locked(0)
        let sweep = SessionWorkerSweep(list: {
            reads.update { $0 += 1 }
            return reads.value == 1 ? nil : []
        }, signal: { _, _ in XCTFail("Nothing to signal") }, sleep: { _ in })
        let outcome = await sweep.stopAll()
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(outcome.result, .noneRunning)
    }

    func testOutcomeResultSeparatesRunningFromUnverified() {
        let worker = SessionWorkerProcess(pid: 1, mode: .runtime, ownerPID: 2)
        XCTAssertEqual(SessionWorkerSweep.Outcome(found: [worker], remaining: []).result, .noneRunning)
        XCTAssertEqual(SessionWorkerSweep.Outcome(found: [worker], remaining: [worker]).result, .stillRunning)
        XCTAssertEqual(SessionWorkerSweep.Outcome(found: [], remaining: [], verified: false).result, .unverified)
    }

    /// Reads the real process table without signalling anything: this test
    /// process is not a KeyPath worker, so it must never list itself.
    func testLiveListingNeverIncludesThisProcess() throws {
        let workers = try XCTUnwrap(SessionWorkerSweep.currentUserSessionWorkers(), "Process table must be readable")
        XCTAssertFalse(workers.contains { $0.pid == getpid() })
        var buffer = try [UInt8](repeating: 0, count: XCTUnwrap(SessionWorkerSweep.argumentMax()))
        let arguments = try XCTUnwrap(SessionWorkerSweep.arguments(of: getpid(), buffer: &buffer))
        // The kernel reports the executable path, which need not equal argv[0].
        XCTAssertTrue(arguments.first?.hasPrefix("/") == true)
        XCTAssertEqual(Array(arguments.dropFirst()), Array(ProcessInfo.processInfo.arguments.dropFirst()))
    }

    /// An unreadable process table proves nothing, so it is not success.
    func testUnreadableProcessTableIsNotSuccess() async {
        let unreadable = SessionWorkerSweep(list: { nil }, signal: { _, _ in XCTFail("Nothing to signal") }, sleep: { _ in })
        let outcome = await unreadable.stopAll()
        XCTAssertFalse(outcome.succeeded)
        XCTAssertFalse(outcome.verified)
    }

    func testTableThatBecomesUnreadableMidSweepIsNotSuccess() async {
        let reads = Locked(0)
        let probe = SessionWorkerProcess(pid: 13284, mode: .capabilities, ownerPID: 30378)
        let sweep = SessionWorkerSweep(list: {
            reads.update { $0 += 1 }
            return reads.value == 1 ? [probe] : nil
        }, signal: { _, _ in }, sleep: { _ in })
        let outcome = await sweep.stopAll()
        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.remaining, [probe])
    }

    func testMalformedKernelArgumentsDoNotCrash() {
        // argc larger than the strings present: returns what is there.
        var bytes = withUnsafeBytes(of: Int32(5)) { Array($0) }
        bytes += Array(Self.trashedExecutable.utf8) + [0] + Array("KeyPath".utf8) + [0]
        XCTAssertEqual(SessionWorkerSweep.parseProcArgs(bytes), [Self.trashedExecutable])
        // No terminating NUL after the executable path.
        let unterminated = withUnsafeBytes(of: Int32(1)) { Array($0) } + Array("/x".utf8)
        XCTAssertNil(SessionWorkerSweep.parseProcArgs(unterminated))
        // Non-UTF8 bytes decode with replacement rather than failing.
        let invalid = withUnsafeBytes(of: Int32(1)) { Array($0) } + [0xFF, 0xFE, 0] + [0x41, 0]
        XCTAssertEqual(SessionWorkerSweep.parseProcArgs(invalid)?.count, 1)
    }
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.lock(); defer { lock.unlock() }; return stored }
    func update(_ body: (inout Value) -> Void) { lock.lock(); body(&stored); lock.unlock() }
}
