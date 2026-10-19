import Darwin
import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class SessionCapsMappingLeaseRecoveryTests: XCTestCase {
    typealias Policy = SessionCapsMappingPolicy
    enum Failure: Error { case unavailable }

    func testDisconnectedServiceRetiresIntentWithoutTouchingReplacement() throws {
        try fixture { lease, fake, owner, _ in
            fake.present = false
            fake.devices = [.init(registryEntryID: 43, vendorID: 51966, productID: 16400,
                                  serialNumber: nil, locationID: 123)]
            fake.failRead = true
            try lease.restore(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID)
            XCTAssertNil(try lease.pendingRecord())
            XCTAssertEqual(fake.writes, 1)
        }
    }

    func testAbsentKeyboardRetiresOnlyWithConclusiveLookup() throws {
        try fixture { lease, fake, owner, _ in
            let record = try lease.pendingRecord()
            fake.devices = []
            fake.present = false
            fake.failLookup = true
            XCTAssertThrowsError(try lease.restore(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID))
            XCTAssertEqual(try lease.pendingRecord(), record)
            fake.failLookup = false
            fake.failRead = true
            try lease.restore(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID)
            XCTAssertNil(try lease.pendingRecord())
            XCTAssertEqual(fake.writes, 1)
        }
    }

    func testFilteredAbsenceDoesNotRetireLiveRegistryEntry() throws {
        try fixture { lease, fake, owner, _ in
            let record = try lease.pendingRecord()
            fake.devices = []
            XCTAssertThrowsError(try lease.restore(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID))
            XCTAssertEqual(try lease.pendingRecord(), record)
            XCTAssertEqual(fake.writes, 1)
        }
    }

    func testDisconnectedServiceRetainsOwnerBootAndMutationGuards() throws {
        try fixture { lease, fake, owner, root in
            let record = try lease.pendingRecord()
            fake.present = false
            let foreign = Policy.Owner(uid: owner.uid, parentPID: 100, workerPID: 102, nonce: "other",
                                       generation: "one", bootSessionUUID: owner.bootSessionUUID)
            XCTAssertThrowsError(try lease.restore(expectedOwner: foreign, bootSessionUUID: owner.bootSessionUUID))
            XCTAssertThrowsError(try lease.restore(expectedOwner: owner, bootSessionUUID: UUID().uuidString))
            let marker = root.appendingPathComponent("caps-mapping-mutation-in-flight.json")
            try JSONEncoder().encode(owner).write(to: marker)
            chmod(marker.path, 0o600)
            XCTAssertThrowsError(try lease.restore(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID)) { error in
                XCTAssertEqual(error as? SessionCapsMappingLease.Refusal, .mutationUncertain)
            }
            XCTAssertEqual(try lease.pendingRecord(), record)
            XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
            XCTAssertEqual(fake.writes, 1)
        }
    }

    /// A refusal before the first write leaves no intent behind, so later stops
    /// are not refused for a mapping KeyPath never applied.
    func testRefusalBeforeAnyWriteLeavesNoPendingIntent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = Fake()
        fake.devices = [fake.device]
        fake.foreignAfterFirstRead = [Policy.Mapping(source: 0x7_0000_0004, destination: 0x7_0000_0005)]
        let owner = Policy.Owner(uid: getuid(), parentPID: 100, workerPID: 101, nonce: "nonce",
                                 generation: "one", bootSessionUUID: UUID().uuidString)
        let lease = SessionCapsMappingLease(directory: root, backend: fake.backend)
        XCTAssertThrowsError(try lease.acquire(owner: owner, configSHA256: String(repeating: "a", count: 64),
                                               device: fake.device))
        { error in
            XCTAssertEqual(error as? Policy.Refusal, .foreignMapping)
        }
        XCTAssertEqual(fake.writes, 0)
        XCTAssertNil(try lease.pendingRecord())
        XCTAssertNoThrow(try lease.restore(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID))
    }

    private final class Fake {
        let device = Policy.DeviceIdentity(registryEntryID: 42, vendorID: 51966, productID: 16400,
                                           serialNumber: nil, locationID: 123)
        var devices: [Policy.DeviceIdentity] = []
        var mappings: [Policy.Mapping] = []
        var present = true
        var failLookup = false
        var failRead = false
        var writes = 0
        var reads = 0
        /// Mappings an outside process applies after the lease's first read.
        var foreignAfterFirstRead: [Policy.Mapping]?
        var backend: SessionCapsMappingLease.Backend {
            .init(enumerate: { self.devices }, read: { device in
                if self.failRead { throw Failure.unavailable }
                self.reads += 1
                if self.reads > 1, let foreign = self.foreignAfterFirstRead { return .init(device: device, mappings: foreign) }
                return .init(device: device, mappings: self.mappings)
            }, write: { _, mappings in
                self.writes += 1
                self.mappings = mappings
            }, registryEntryExists: { id in
                XCTAssertEqual(id, self.device.registryEntryID)
                if self.failLookup { throw Failure.unavailable }
                return self.present
            })
        }
    }

    private func fixture(_ body: (SessionCapsMappingLease, Fake, Policy.Owner, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = Fake()
        fake.devices = [fake.device]
        let owner = Policy.Owner(uid: getuid(), parentPID: 100, workerPID: 101, nonce: "nonce",
                                 generation: "one", bootSessionUUID: UUID().uuidString)
        let lease = SessionCapsMappingLease(directory: root, backend: fake.backend)
        _ = try lease.acquire(owner: owner, configSHA256: String(repeating: "a", count: 64), device: fake.device)
        try body(lease, fake, owner, root)
    }
}
