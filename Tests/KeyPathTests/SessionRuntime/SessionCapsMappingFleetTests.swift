import Darwin
import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class SessionCapsMappingFleetTests: XCTestCase {
    typealias Policy = SessionCapsMappingPolicy

    private final class Fake {
        let devices: [Policy.DeviceIdentity] = (1 ... 3).map {
            .init(registryEntryID: UInt64($0 + 100), vendorID: UInt32($0), productID: 1,
                  serialNumber: nil, locationID: UInt32($0 + 200))
        }

        var connected = Set<UInt64>([101, 102])
        var mappings: [UInt64: [Policy.Mapping]] = [:]
        var writes: [UInt64] = []
        var failReadOnce: UInt64?
        var backend: SessionCapsMappingLease.Backend {
            .init(enumerate: { self.devices.filter { self.connected.contains($0.registryEntryID) } },
                  read: { device in
                      if self.failReadOnce == device.registryEntryID {
                          self.failReadOnce = nil
                          throw NSError(domain: "fixture", code: 1)
                      }
                      return .init(device: device, mappings: self.mappings[device.registryEntryID] ?? [])
                  },
                  write: { device, rows in
                      self.writes.append(device.registryEntryID)
                      self.mappings[device.registryEntryID] = rows
                  },
                  registryEntryExists: { self.connected.contains($0) })
        }
    }

    private func fixture(_ body: (SessionCapsMappingFleet, Fake, Policy.Owner) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = Fake()
        let owner = Policy.Owner(uid: getuid(), parentPID: 100, workerPID: 101, nonce: "fleet",
                                 generation: "fleet", bootSessionUUID: UUID().uuidString)
        try body(.init(directory: root, backend: fake.backend), fake, owner)
    }

    func testSeveralKeyboardsAcquireAndRestoreIndependently() throws {
        try fixture { fleet, fake, owner in
            let digest = String(repeating: "a", count: 64)
            let result = try fleet.acquire(owner: owner, configSHA256: digest, devices: Array(fake.devices.prefix(2)),
                                           intermediate: Policy.f18)
            XCTAssertEqual(result.records.count, 2)
            XCTAssertTrue(result.failures.isEmpty)
            XCTAssertEqual(Set(fake.writes), [101, 102])
            XCTAssertEqual(try fleet.activeDeviceIDs(bootSessionUUID: owner.bootSessionUUID, processAlive: { _ in true }), [101, 102])

            fake.connected.remove(101)
            let afterUnplug = try fleet.reconcile(owner: owner, configSHA256: digest, devices: [fake.devices[1]],
                                                  intermediate: Policy.f18, bootSessionUUID: owner.bootSessionUUID)
            XCTAssertEqual(afterUnplug.records.map(\.device.registryEntryID), [102])
            XCTAssertEqual(fake.mappings[102], [.init(source: Policy.caps, destination: Policy.f18)])
            try fleet.restore(owner: owner, bootSessionUUID: owner.bootSessionUUID)
            XCTAssertEqual(fake.mappings[102], [])
            XCTAssertTrue(try fleet.pendingRecords(owner: owner).isEmpty)
        }
    }

    func testHotPlugAddsKeyboardWithoutReplacingExistingMapping() throws {
        try fixture { fleet, fake, owner in
            let digest = String(repeating: "b", count: 64)
            _ = try fleet.acquire(owner: owner, configSHA256: digest, devices: [fake.devices[0]],
                                  intermediate: Policy.f18)
            fake.connected.insert(103)
            let paused = try fleet.reconcile(owner: owner, configSHA256: digest,
                                             devices: [fake.devices[0], fake.devices[2]],
                                             intermediate: Policy.f18, bootSessionUUID: owner.bootSessionUUID,
                                             allowNewDevices: false)
            XCTAssertEqual(paused.records.count, 1)
            let active = try fleet.reconcile(owner: owner, configSHA256: digest,
                                             devices: [fake.devices[0], fake.devices[2]],
                                             intermediate: Policy.f18, bootSessionUUID: owner.bootSessionUUID)
            XCTAssertEqual(Set(active.records.map(\.device.registryEntryID)), [101, 103])
            XCTAssertEqual(fake.writes.filter { $0 == 101 }.count, 1)
        }
    }

    func testOneReadFailureRetiresOnlyThatDevice() throws {
        try fixture { fleet, fake, owner in
            let devices = Array(fake.devices.prefix(2))
            _ = try fleet.acquire(owner: owner, configSHA256: String(repeating: "a", count: 64),
                                  devices: devices, intermediate: Policy.f18)
            fake.failReadOnce = devices[0].registryEntryID
            let coverage = try fleet.reconcile(owner: owner, configSHA256: String(repeating: "a", count: 64),
                                               devices: devices, intermediate: Policy.f18,
                                               bootSessionUUID: owner.bootSessionUUID, allowNewDevices: false)
            XCTAssertEqual(coverage.records.map(\.device.registryEntryID), [devices[1].registryEntryID])
            XCTAssertNotNil(coverage.failures[devices[0].registryEntryID])
            XCTAssertEqual(fake.mappings[devices[0].registryEntryID], [])
            XCTAssertEqual(fake.mappings[devices[1].registryEntryID], [.init(source: Policy.caps, destination: Policy.f18)])
            try fleet.restore(owner: owner, bootSessionUUID: owner.bootSessionUUID)
        }
    }

    func testExistingSelectionKeepsSingleKeyboardScopeUntilExplicitlyChanged() {
        let domain = "caps-fleet-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        XCTAssertFalse(SessionCapsRuntimeSupport.selectedKeyboardOnly(defaults: defaults))
        defaults.set(Data("legacy".utf8), forKey: SessionCapsRuntimeSupport.selectionKey)
        XCTAssertTrue(SessionCapsRuntimeSupport.selectedKeyboardOnly(defaults: defaults))
        defaults.set(false, forKey: SessionCapsRuntimeSupport.selectedKeyboardOnlyKey)
        XCTAssertFalse(SessionCapsRuntimeSupport.selectedKeyboardOnly(defaults: defaults))
    }

    func testLegacyRecoveryFailureStillRunsFleetRecovery() {
        var fleetRan = false
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.recoverIndependent(
            legacy: { throw NSError(domain: "legacy", code: 1) },
            fleet: { fleetRan = true }
        ))
        XCTAssertTrue(fleetRan)
    }

    func testConflictingKeyboardDoesNotDisableOtherKeyboard() throws {
        try fixture { fleet, fake, owner in
            fake.mappings[102] = [.init(source: Policy.caps, destination: 0x7_0000_00E0)]
            let result = try fleet.acquire(owner: owner, configSHA256: String(repeating: "c", count: 64),
                                           devices: Array(fake.devices.prefix(2)), intermediate: Policy.f18)
            XCTAssertEqual(result.records.map(\.device.registryEntryID), [101])
            XCTAssertNotNil(result.failures[102])
            XCTAssertEqual(fake.mappings[102], [.init(source: Policy.caps, destination: 0x7_0000_00E0)])
            try fleet.restore(owner: owner, bootSessionUUID: owner.bootSessionUUID)
            XCTAssertEqual(fake.mappings[101], [])
            XCTAssertEqual(fake.mappings[102], [.init(source: Policy.caps, destination: 0x7_0000_00E0)])
        }
    }

    func testCrashRecoveryRestoresEveryKeyboard() throws {
        try fixture { fleet, fake, owner in
            _ = try fleet.acquire(owner: owner, configSHA256: String(repeating: "d", count: 64),
                                  devices: Array(fake.devices.prefix(2)), intermediate: Policy.f18)
            try fleet.recover(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID)
            XCTAssertEqual(fake.mappings[101], [])
            XCTAssertEqual(fake.mappings[102], [])
            XCTAssertTrue(try fleet.pendingRecords(owner: owner).isEmpty)
        }
    }

    func testUnreadableJournalDoesNotBlockOtherRestores() throws {
        try fixture { fleet, fake, owner in
            _ = try fleet.acquire(owner: owner, configSHA256: String(repeating: "f", count: 64),
                                  devices: Array(fake.devices.prefix(2)), intermediate: Policy.f18)
            let bad = fleet.directory.appendingPathComponent("keyboards/103", isDirectory: true)
            try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            let journal = bad.appendingPathComponent("caps-mapping-intent.json")
            try Data("invalid".utf8).write(to: journal)
            chmod(journal.path, 0o600)
            XCTAssertThrowsError(try fleet.recover(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID))
            XCTAssertEqual(fake.mappings[101], [])
            XCTAssertEqual(fake.mappings[102], [])
            XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
        }
    }

    func testParentTerminationGuardExcludesNewDeviceWriter() throws {
        try fixture { fleet, fake, owner in
            let root = SessionCapsMappingLease(directory: fleet.directory, backend: fake.backend)
            let guardHandle = try root.acquireTerminationGuard(expectedOwner: owner)
            defer { guardHandle.release() }
            XCTAssertThrowsError(try fleet.acquire(owner: owner, configSHA256: String(repeating: "e", count: 64),
                                                   devices: [fake.devices[0]], intermediate: Policy.f18))
            { error in
                XCTAssertEqual(error as? SessionCapsMappingLease.Refusal, .busy)
            }
            XCTAssertTrue(fake.writes.isEmpty)
        }
    }

    func testKeyboardExceptionSurvivesReplugButDistinguishesPorts() {
        let original = Policy.DeviceIdentity(registryEntryID: 101, vendorID: 42, productID: 5,
                                             serialNumber: nil, locationID: 100)
        let replugged = Policy.DeviceIdentity(registryEntryID: 999, vendorID: 42, productID: 5,
                                              serialNumber: nil, locationID: 100)
        let otherPort = Policy.DeviceIdentity(registryEntryID: 1000, vendorID: 42, productID: 5,
                                              serialNumber: nil, locationID: 200)
        XCTAssertEqual(SessionCapsRuntimeSupport.preferenceID(original), SessionCapsRuntimeSupport.preferenceID(replugged))
        XCTAssertNotEqual(SessionCapsRuntimeSupport.preferenceID(original), SessionCapsRuntimeSupport.preferenceID(otherPort))
        let serialOne = Policy.DeviceIdentity(registryEntryID: 101, vendorID: 42, productID: 5,
                                              serialNumber: "unique", locationID: 100)
        let serialMoved = Policy.DeviceIdentity(registryEntryID: 102, vendorID: 42, productID: 5,
                                                serialNumber: "unique", locationID: 200)
        XCTAssertNotEqual(SessionCapsRuntimeSupport.preferenceID(serialOne), SessionCapsRuntimeSupport.preferenceID(serialMoved))
    }

    func testStatusWarnsOnlyForUncoveredKeyboards() {
        XCTAssertNil(ServiceLifecycleCoordinator.capsCoverageWarning(.init(eligible: 3, covered: 3, withheld: 0)))
        XCTAssertNil(ServiceLifecycleCoordinator.capsCoverageWarning(.init(eligible: 0, covered: 0, withheld: 0)))
        XCTAssertTrue(ServiceLifecycleCoordinator.capsCoverageWarning(.init(eligible: 3, covered: 2, withheld: 0))?
            .contains("2 of 3") == true)
        XCTAssertTrue(ServiceLifecycleCoordinator.capsCoverageWarning(.init(eligible: 2, covered: 2, withheld: 1))?
            .contains("1 connected keyboard") == true)
    }

    /// Opt-in hardware qualification on the lab mini. Each original mapping
    /// is read before the write and verified after an exact-owner restore.
    func testLiveAttachedKeyboardsAcquireAndRestore() throws {
        guard ProcessInfo.processInfo.environment["KEYPATH_LIVE_CAPS_FLEET"] == "1" else {
            throw XCTSkip("Set KEYPATH_LIVE_CAPS_FLEET=1 to test attached physical keyboards")
        }
        let backend = SessionCapsHIDUtilTransport.backend()
        let inventory = try SessionCapsHIDUtilTransport.keyboards()
        let devices = inventory.keyboards.map(\.device)
        guard inventory.withheld == 0, devices.count >= 2,
              inventory.keyboards.contains(where: { $0.name.contains("KeyPath Physical HID Fixture") })
        else {
            throw XCTSkip("Requires the lab mini's eligible keyboards and physical HID fixture")
        }
        try SessionCapsRuntimeSupport.requirePhysicalAllUp()
        let original = try Dictionary(uniqueKeysWithValues: devices.map { device in
            try (device.registryEntryID, backend.read(device).mappings)
        })
        guard original.values.allSatisfy({ rows in !rows.contains(where: { $0.source == Policy.caps }) }) else {
            throw XCTSkip("Another Caps Lock mapping is already present")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("keypath-live-caps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let boot = try SessionCapsRuntimeSupport.bootSessionUUID()
        let owner = Policy.Owner(uid: getuid(), parentPID: getppid(), workerPID: getpid(),
                                 nonce: UUID().uuidString, generation: UUID().uuidString, bootSessionUUID: boot)
        let fleet = SessionCapsMappingFleet(directory: root, backend: backend)
        do {
            let result = try fleet.acquire(owner: owner, configSHA256: String(repeating: "a", count: 64),
                                           devices: devices, intermediate: Policy.f18)
            XCTAssertEqual(result.records.count, devices.count, "Uncovered devices: \(result.failures)")
            for device in devices {
                let rows = try backend.read(device).mappings
                XCTAssertTrue(rows.contains(.init(source: Policy.caps, destination: Policy.f18)))
            }
            try fleet.restore(owner: owner, bootSessionUUID: boot)
            for device in devices {
                XCTAssertEqual(try backend.read(device).mappings, original[device.registryEntryID])
            }
            try FileManager.default.removeItem(at: root)
        } catch {
            try? fleet.restore(owner: owner, bootSessionUUID: boot)
            throw error
        }
    }
}
