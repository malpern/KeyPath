import Darwin
import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class SessionCapsTerminationGuardTests: XCTestCase {
    typealias Policy = SessionCapsMappingPolicy
    private enum Failure: Error { case unexpectedHIDAccess }

    func testMissingDirectoryStillExcludesFirstAcquisition() throws {
        try fixture { lease, owner, directory in
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
            let guardHandle = try lease.acquireTerminationGuard(expectedOwner: owner)
            defer { guardHandle.release() }
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
            let competitor = makeLease(directory)
            assertRefusal(.busy) {
                _ = try competitor.acquire(owner: owner, configSHA256: String(repeating: "a", count: 64), device: device)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("caps-mapping-intent.json").path))
        }
    }

    func testMarkerRefusesAndPreservesEvidenceWithoutJournal() throws {
        try fixture { lease, owner, directory in
            try createDirectory(directory)
            let marker = directory.appendingPathComponent("caps-mapping-mutation-in-flight.json")
            let evidence = try JSONEncoder().encode(owner)
            try evidence.write(to: marker)
            XCTAssertEqual(chmod(marker.path, 0o600), 0)
            assertRefusal(.mutationUncertain) { _ = try lease.acquireTerminationGuard(expectedOwner: owner) }
            XCTAssertEqual(try Data(contentsOf: marker), evidence)
            // A failed guard acquisition must release its lock.
            XCTAssertNil(try makeLease(directory).pendingRecord())
        }
    }

    func testJournalRequiresExactOwnerAndRetainsIntent() throws {
        try fixture { lease, owner, directory in
            try createDirectory(directory)
            let record = try Policy.acquire(original: [], device: device, devices: [device],
                                            owner: owner, effectiveConfigSHA256: String(repeating: "a", count: 64))
            let journal = directory.appendingPathComponent("caps-mapping-intent.json")
            let evidence = try JSONEncoder().encode(record)
            try evidence.write(to: journal)
            XCTAssertEqual(chmod(journal.path, 0o600), 0)
            let other = Policy.Owner(uid: owner.uid, parentPID: owner.parentPID, workerPID: owner.workerPID,
                                     nonce: "other", generation: owner.generation, bootSessionUUID: owner.bootSessionUUID)
            assertRefusal(.wrongOwner) { _ = try lease.acquireTerminationGuard(expectedOwner: other) }
            let guardHandle = try lease.acquireTerminationGuard(expectedOwner: owner)
            guardHandle.release()
            XCTAssertEqual(try Data(contentsOf: journal), evidence)
        }
    }

    func testGuardSurvivesDelayedExitAndReleaseIsIdempotent() throws {
        try fixture { lease, owner, directory in
            let competitor = makeLease(directory)
            var cleanupGuard: SessionCapsMappingLease.TerminationGuard?
            do {
                let guardHandle = try lease.acquireTerminationGuard(expectedOwner: owner)
                // Simulate a successful signal followed by an exit wait that
                // times out: cleanup must retain the exclusion after returning.
                cleanupGuard = guardHandle
            }
            assertRefusal(.busy) { _ = try competitor.acquireTerminationGuard(expectedOwner: owner) }
            assertRefusal(.busy) { _ = try competitor.pendingRecord() }
            // The delayed exit has now been observed.
            cleanupGuard?.release()
            let next = try competitor.acquireTerminationGuard(expectedOwner: owner)
            defer { next.release() }
            // Releasing/deinitializing the old guard must not close a reused fd
            // or unlock the new guard.
            cleanupGuard?.release()
            cleanupGuard = nil
            assertRefusal(.busy) { _ = try lease.pendingRecord() }
        }
    }

    func testDeinitReleasesGuard() throws {
        try fixture { lease, owner, directory in
            var guardHandle: SessionCapsMappingLease.TerminationGuard? = try lease.acquireTerminationGuard(expectedOwner: owner)
            XCTAssertNotNil(guardHandle)
            assertRefusal(.busy) { _ = try makeLease(directory).pendingRecord() }
            guardHandle = nil
            XCTAssertNil(try makeLease(directory).pendingRecord())
        }
    }

    func testUnsafeDirectoryAndLockAreRefused() throws {
        try fixture { lease, owner, directory in
            try createDirectory(directory)
            XCTAssertEqual(chmod(directory.path, 0o755), 0)
            assertRefusal(.unsafeDirectory) { _ = try lease.acquireTerminationGuard(expectedOwner: owner) }
            XCTAssertEqual(chmod(directory.path, 0o700), 0)
            let lock = directory.appendingPathComponent("caps-mapping.lock")
            try Data().write(to: lock)
            XCTAssertEqual(chmod(lock.path, 0o644), 0)
            assertRefusal(.unsafeFile) { _ = try lease.acquireTerminationGuard(expectedOwner: owner) }
        }
    }

    func testActualChildCannotAcquireUntilGuardIsReleased() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
            throw XCTSkip("System Python is unavailable for the subprocess flock check")
        }
        try fixture { lease, owner, directory in
            let guardHandle = try lease.acquireTerminationGuard(expectedOwner: owner)
            defer { guardHandle.release() }
            let lockPath = directory.appendingPathComponent("caps-mapping.lock").path
            XCTAssertEqual(try childLockStatus(lockPath), 75)
            guardHandle.release()
            XCTAssertEqual(try childLockStatus(lockPath), 0)
        }
    }

    private func childLockStatus(_ path: String) throws -> Int32 {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        child.arguments = ["-c", """
        import fcntl, os, sys
        fd = os.open(sys.argv[1], os.O_RDWR)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            sys.exit(75)
        finally:
            os.close(fd)
        """, path]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        child.waitUntilExit()
        return child.terminationStatus
    }

    private var device: Policy.DeviceIdentity {
        .init(registryEntryID: 42, vendorID: 51966, productID: 16400, serialNumber: nil, locationID: 123)
    }

    private func makeLease(_ directory: URL) -> SessionCapsMappingLease {
        .init(directory: directory, backend: .init(
            enumerate: { throw Failure.unexpectedHIDAccess },
            read: { _ in throw Failure.unexpectedHIDAccess },
            write: { _, _ in throw Failure.unexpectedHIDAccess }
        ))
    }

    private func createDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
    }

    private func assertRefusal(_ expected: SessionCapsMappingLease.Refusal, _ operation: () throws -> Void,
                               file: StaticString = #filePath, line: UInt = #line)
    {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? SessionCapsMappingLease.Refusal, expected, file: file, line: line)
        }
    }

    private func fixture(_ body: (SessionCapsMappingLease, Policy.Owner, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = Policy.Owner(uid: getuid(), parentPID: 100, workerPID: 101, nonce: "nonce",
                                 generation: "one", bootSessionUUID: UUID().uuidString)
        try body(makeLease(directory), owner, directory)
    }
}
