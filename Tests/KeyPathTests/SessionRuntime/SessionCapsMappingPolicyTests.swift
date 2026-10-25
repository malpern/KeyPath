import Foundation
import KeyPathCore
@preconcurrency import XCTest

final class SessionCapsMappingPolicyTests: XCTestCase {
    private typealias Policy = SessionCapsMappingPolicy
    private let device = Policy.DeviceIdentity(registryEntryID: 42, vendorID: 0x303A, productID: 0x4002,
                                               serialNumber: "fixture-1", locationID: 123)
    private let owner = Policy.Owner(uid: 502, parentPID: 100, workerPID: 101, nonce: "session-nonce",
                                     generation: "worker-1", bootSessionUUID: "A7B944DF-471A-4C22-B9F3-A4EE5522F775")
    private let digest = String(repeating: "a", count: 64)
    private let unrelated = [Policy.Mapping(source: 0x7_0000_0004, destination: 0x7_0000_0005),
                             Policy.Mapping(source: 0xC_0000_00E9, destination: 0xC_0000_00EA)]

    private func acquire(_ original: [Policy.Mapping] = []) throws -> Policy.Record {
        try Policy.acquire(original: original, device: device, devices: [device], owner: owner, effectiveConfigSHA256: digest)
    }

    private func assertRefusal(_ expected: Policy.Refusal, _ body: () throws -> some Any, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? Policy.Refusal, expected, file: file, line: line)
        }
    }

    func testPreservesUnrelatedKeyboardAndConsumerMappingsInExactOrder() throws {
        let record = try acquire(unrelated)
        XCTAssertEqual(record.original, unrelated)
        XCTAssertEqual(record.applied, unrelated + [.init(source: 0x7_0000_0039, destination: 0x7_0000_006D)])
        XCTAssertEqual(try Policy.restore(record: record, current: record.applied, device: device,
                                          bootSessionUUID: owner.bootSessionUUID), unrelated)
        let empty = try acquire()
        XCTAssertEqual(try Policy.restore(record: empty, current: empty.applied, device: device,
                                          bootSessionUUID: owner.bootSessionUUID), [])
    }

    func testRefusesCapsSourceAndEitherSideOfF18IncludingExistingDesiredMapping() {
        assertRefusal(.capsAlreadyMapped) { try acquire([.init(source: Policy.caps, destination: 0x7_0000_0004)]) }
        assertRefusal(.capsAlreadyMapped) { try acquire([.init(source: Policy.caps, destination: Policy.f18)]) }
        assertRefusal(.intermediateCollision) { try acquire([.init(source: Policy.f18, destination: 0x7_0000_0004)]) }
        assertRefusal(.intermediateCollision) { try acquire([.init(source: 0x7_0000_0004, destination: Policy.f18)]) }
    }

    func testChosenIntermediateIsReservedInsteadOfF18() throws {
        let f19 = Policy.packed(110)
        let record = try Policy.acquire(original: [.init(source: Policy.f18, destination: 0x7_0000_0004)], device: device,
                                        devices: [device], owner: owner, effectiveConfigSHA256: digest, intermediate: f19)
        XCTAssertEqual(record.version, 2)
        XCTAssertEqual(record.intermediate, f19)
        XCTAssertEqual(record.applied.last, .init(source: Policy.caps, destination: f19))
        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(Policy.Record.self, from: data), record)
        assertRefusal(.intermediateCollision) {
            try Policy.acquire(original: [.init(source: 0x7_0000_0004, destination: f19)], device: device,
                               devices: [device], owner: owner, effectiveConfigSHA256: digest, intermediate: f19)
        }
        // F21 has no macOS keycode; Caps itself and other pages are not intermediates.
        for bad in [Policy.packed(112), Policy.caps, 0xC_0000_006E] {
            assertRefusal(.invalidIntermediate) {
                try Policy.acquire(original: [], device: device, devices: [device], owner: owner,
                                   effectiveConfigSHA256: digest, intermediate: bad)
            }
        }
        // A record whose intermediate disagrees with its applied row is refused.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["intermediate"] = Policy.f18
        XCTAssertThrowsError(try JSONDecoder().decode(Policy.Record.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    /// A journal written before the intermediate was a choice has no
    /// `intermediate` field. It must still restore, as F18.
    func testVersionOneJournalDecodesAsF18AndKeepsItsShape() throws {
        let record = try acquire(unrelated)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        object["version"] = 1
        object.removeValue(forKey: "intermediate")
        let legacy = try JSONDecoder().decode(Policy.Record.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(legacy.version, 1)
        XCTAssertEqual(legacy.intermediate, Policy.f18)
        XCTAssertEqual(try Policy.restore(record: legacy, current: legacy.applied, device: device,
                                          bootSessionUUID: owner.bootSessionUUID), unrelated)
        let reencoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        XCTAssertNil(reencoded["intermediate"])
        object["intermediate"] = Policy.f18
        XCTAssertThrowsError(try JSONDecoder().decode(Policy.Record.self, from: JSONSerialization.data(withJSONObject: object)),
                             "A version-1 record never carried an intermediate field")
    }

    func testDuplicateSourcesAndMalformedUsagesAreRefusedWithoutDiscardingRows() {
        assertRefusal(.duplicateSource) { try acquire([unrelated[0], unrelated[0]]) }
        assertRefusal(.duplicateSource) { try acquire([unrelated[0], .init(source: unrelated[0].source, destination: 0x7_0000_0006)]) }
        for bad: UInt64 in [0, 57, 0x7_0000_0000, 0x7_0001_0000, UInt64.max] {
            assertRefusal(.malformedMapping) { try acquire([.init(source: bad, destination: 0x7_0000_0004)]) }
            assertRefusal(.malformedMapping) { try acquire([.init(source: 0x7_0000_0004, destination: bad)]) }
        }
        // Multiple independent sources may intentionally share an unrelated target.
        XCTAssertNoThrow(try acquire([unrelated[0], .init(source: 0x7_0000_0006, destination: unrelated[0].destination)]))
    }

    func testRestorationRefusesForeignAdditionRemovalReplacementAndReordering() throws {
        let record = try acquire(unrelated)
        let changed = [record.applied + [.init(source: 0x7_0000_0006, destination: 0x7_0000_0007)],
                       record.original, Array(record.applied.reversed()),
                       unrelated + [.init(source: Policy.caps, destination: 0x7_0000_0008)]]
        for current in changed {
            assertRefusal(.foreignMapping) {
                try Policy.restore(record: record, current: current, device: device, bootSessionUUID: owner.bootSessionUUID)
            }
            XCTAssertNotEqual(current, record.applied)
        }
    }

    func testRegistryReconnectionIdentityChangesAndDifferentBootCannotRestoreSnapshot() throws {
        let record = try acquire()
        let changed = [Policy.DeviceIdentity(registryEntryID: 43, vendorID: device.vendorID, productID: device.productID,
                                             serialNumber: device.serialNumber, locationID: device.locationID),
                       Policy.DeviceIdentity(registryEntryID: 42, vendorID: device.vendorID, productID: device.productID,
                                             serialNumber: "replacement", locationID: device.locationID)]
        for replacement in changed {
            assertRefusal(.differentDevice) {
                try Policy.restore(record: record, current: record.applied, device: replacement, bootSessionUUID: owner.bootSessionUUID)
            }
        }
        assertRefusal(.differentBoot) {
            try Policy.restore(record: record, current: record.applied, device: device,
                               bootSessionUUID: "9EBEF895-E889-4630-A8F7-EC1323132CF4")
        }
    }

    func testAcquisitionRequiresFreshUnambiguousCorroboratedDevice() {
        for devices in [[], [device, device]] {
            assertRefusal(.ambiguousDevice) {
                try Policy.acquire(original: [], device: device, devices: devices, owner: owner, effectiveConfigSHA256: digest)
            }
        }
        let weak = Policy.DeviceIdentity(registryEntryID: 42, vendorID: 0x303A, productID: 0x4002, serialNumber: nil, locationID: nil)
        assertRefusal(.invalidDevice) {
            try Policy.acquire(original: [], device: weak, devices: [weak], owner: owner, effectiveConfigSHA256: digest)
        }
        let sibling = Policy.DeviceIdentity(registryEntryID: 43, vendorID: device.vendorID, productID: device.productID,
                                            serialNumber: "fixture-2", locationID: 124)
        XCTAssertNoThrow(try Policy.acquire(original: [], device: device, devices: [device, sibling], owner: owner, effectiveConfigSHA256: digest))
        let indistinguishable = Policy.DeviceIdentity(registryEntryID: 43, vendorID: device.vendorID, productID: device.productID,
                                                      serialNumber: device.serialNumber, locationID: device.locationID)
        assertRefusal(.ambiguousDevice) {
            try Policy.acquire(original: [], device: device, devices: [device, indistinguishable], owner: owner, effectiveConfigSHA256: digest)
        }
    }

    func testDurableRecordRoundTripAndTamperedOrIncompleteRecordRefusal() throws {
        let record = try acquire(unrelated)
        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(Policy.Record.self, from: data), record)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["version", "device", "owner", "effectiveConfigSHA256", "intermediate", "original", "applied"] {
            var incomplete = object
            incomplete.removeValue(forKey: key)
            XCTAssertThrowsError(try JSONDecoder().decode(Policy.Record.self, from: JSONSerialization.data(withJSONObject: incomplete)))
        }
        for change: [String: Any] in [["version": 3], ["applied": []], ["effectiveConfigSHA256": "bad"], ["unowned": true]] {
            var tampered = object
            tampered.merge(change) { _, new in new }
            XCTAssertThrowsError(try JSONDecoder().decode(Policy.Record.self, from: JSONSerialization.data(withJSONObject: tampered)))
        }
    }

    func testAcquisitionRequiresBoundedOwnerAndEffectiveConfigurationIdentity() {
        let invalidOwners = [Policy.Owner(uid: 0, parentPID: 100, workerPID: 101, nonce: "nonce", generation: "worker-1", bootSessionUUID: owner.bootSessionUUID),
                             Policy.Owner(uid: 502, parentPID: 101, workerPID: 101, nonce: "nonce", generation: "worker-1", bootSessionUUID: owner.bootSessionUUID),
                             Policy.Owner(uid: 502, parentPID: -1, workerPID: 101, nonce: "nonce", generation: "worker-1", bootSessionUUID: owner.bootSessionUUID),
                             Policy.Owner(uid: 502, parentPID: 100, workerPID: 0, nonce: "nonce", generation: "worker-1", bootSessionUUID: owner.bootSessionUUID),
                             Policy.Owner(uid: 502, parentPID: 100, workerPID: 101, nonce: "", generation: "worker-1", bootSessionUUID: owner.bootSessionUUID),
                             Policy.Owner(uid: 502, parentPID: 100, workerPID: 101, nonce: " malformed ", generation: "worker-1", bootSessionUUID: owner.bootSessionUUID),
                             Policy.Owner(uid: 502, parentPID: 100, workerPID: 101, nonce: String(repeating: "a", count: 129), generation: "worker-1", bootSessionUUID: owner.bootSessionUUID),
                             Policy.Owner(uid: 502, parentPID: 100, workerPID: 101, nonce: "nonce", generation: "", bootSessionUUID: owner.bootSessionUUID),
                             Policy.Owner(uid: 502, parentPID: 100, workerPID: 101, nonce: "nonce", generation: String(repeating: "a", count: 129), bootSessionUUID: owner.bootSessionUUID),
                             Policy.Owner(uid: 502, parentPID: 100, workerPID: 101, nonce: "nonce", generation: "worker-1", bootSessionUUID: "unknown")]
        for invalid in invalidOwners {
            assertRefusal(.invalidOwner) {
                try Policy.acquire(original: [], device: device, devices: [device], owner: invalid, effectiveConfigSHA256: digest)
            }
        }
        for invalidDigest in ["", String(repeating: "0", count: 65), String(repeating: "a", count: 63), String(repeating: "z", count: 64)] {
            assertRefusal(.invalidConfigDigest) {
                try Policy.acquire(original: [], device: device, devices: [device], owner: owner, effectiveConfigSHA256: invalidDigest)
            }
        }
    }

    func testMalformedMappingJSONCannotLoseUnknownRowsOrCoerceMissingFields() throws {
        let src = "HIDKeyboardModifierMappingSrc", dst = "HIDKeyboardModifierMappingDst"
        for row: [String: Any] in [[src: Policy.caps], [src: Policy.caps, dst: "109"],
                                   [src: true, dst: Policy.f18], [src: -1, dst: Policy.f18],
                                   [src: Policy.caps, dst: Policy.f18, "Unknown": 1]]
        {
            XCTAssertThrowsError(try JSONDecoder().decode(Policy.Mapping.self, from: JSONSerialization.data(withJSONObject: row)))
        }
    }
}
