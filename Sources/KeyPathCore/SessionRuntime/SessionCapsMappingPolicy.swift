import Foundation

/// Pure decisions for one device-scoped Caps substitution. Transport and durable
/// intent/readback belong to the session lifecycle; this does not authorize writes.
public enum SessionCapsMappingPolicy {
    // Packed keyboard-page usages, also exercised by caps-path-trial.py.
    public static let caps: UInt64 = 0x7_0000_0039
    public static let f18: UInt64 = 0x7_0000_006D

    public enum Refusal: Error, Equatable {
        case malformedMapping, duplicateSource, capsAlreadyMapped, f18Collision
        case invalidDevice, ambiguousDevice, invalidOwner, invalidConfigDigest
        case invalidRecord, differentBoot, differentDevice, foreignMapping
    }

    public struct Mapping: Codable, Sendable, Equatable {
        public let source: UInt64
        public let destination: UInt64

        public init(source: UInt64, destination: UInt64) {
            self.source = source
            self.destination = destination
        }

        private enum CodingKeys: String, CodingKey {
            case source = "HIDKeyboardModifierMappingSrc"
            case destination = "HIDKeyboardModifierMappingDst"
        }

        public init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: Field.self)
            guard Set(fields.allKeys.map(\.stringValue)) == Set([CodingKeys.source.rawValue, CodingKeys.destination.rawValue]) else {
                throw Refusal.malformedMapping
            }
            let values = try decoder.container(keyedBy: CodingKeys.self)
            source = try values.decode(UInt64.self, forKey: .source)
            destination = try values.decode(UInt64.self, forKey: .destination)
            guard Self.validUsage(source), Self.validUsage(destination) else { throw Refusal.malformedMapping }
        }

        fileprivate static func validUsage(_ value: UInt64) -> Bool {
            // Preserve standard and vendor usage pages without guessing a key whitelist.
            (1 ... 0xFFFF).contains(value >> 32) && (1 ... 0xFFFF).contains(value & 0xFFFF_FFFF)
        }
    }

    /// Registry identity must be the IOHID event-service ID, not a USB ancestor.
    /// It is scoped to bootSessionUUID, never a reconnect locator.
    /// Serial/location and VID/PID corroborate the instance; VID/PID alone is insufficient.
    public struct DeviceIdentity: Codable, Sendable, Equatable {
        public let registryEntryID: UInt64
        public let vendorID: UInt32
        public let productID: UInt32
        public let serialNumber: String?
        public let locationID: UInt32?

        public init(registryEntryID: UInt64, vendorID: UInt32, productID: UInt32,
                    serialNumber: String?, locationID: UInt32?)
        {
            self.registryEntryID = registryEntryID
            self.vendorID = vendorID
            self.productID = productID
            self.serialNumber = serialNumber
            self.locationID = locationID
        }

        fileprivate var isValid: Bool {
            registryEntryID != 0 && vendorID != 0 && vendorID <= 0xFFFF && productID <= 0xFFFF
                && (serialNumber.map(Self.validSerial) ?? true)
                && (serialNumber != nil || (locationID ?? 0) != 0)
        }

        private static func validSerial(_ value: String) -> Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= 1024
        }
    }

    public struct Owner: Codable, Sendable, Equatable {
        public let uid: UInt32
        public let parentPID: Int32
        public let workerPID: Int32
        public let nonce: String
        public let generation: String
        public let bootSessionUUID: String

        public init(uid: UInt32, parentPID: Int32, workerPID: Int32, nonce: String,
                    generation: String, bootSessionUUID: String)
        {
            self.uid = uid
            self.parentPID = parentPID
            self.workerPID = workerPID
            self.nonce = nonce
            self.generation = generation
            self.bootSessionUUID = bootSessionUUID
        }

        fileprivate var isValid: Bool {
            uid != 0 && parentPID > 0 && workerPID > 0 && parentPID != workerPID
                && Self.validToken(nonce) && Self.validToken(generation)
                && UUID(uuidString: bootSessionUUID) != nil
        }

        private static func validToken(_ value: String) -> Bool {
            !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy {
                (48 ... 57).contains($0) || (65 ... 90).contains($0) || (97 ... 122).contains($0) || $0 == 45 || $0 == 95
            }
        }
    }

    /// Persist before mutation, then independently verify `applied` before running.
    /// A record is intent, not proof that the mapping was written or that a PID lives.
    public struct Record: Codable, Sendable, Equatable {
        public let version: Int
        public let device: DeviceIdentity
        public let owner: Owner
        public let effectiveConfigSHA256: String
        public let original: [Mapping]
        public let applied: [Mapping]

        fileprivate init(device: DeviceIdentity, owner: Owner, effectiveConfigSHA256: String, original: [Mapping]) {
            version = 1
            self.device = device
            self.owner = owner
            self.effectiveConfigSHA256 = effectiveConfigSHA256
            self.original = original
            applied = original + [Mapping(source: caps, destination: f18)]
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case version, device, owner, effectiveConfigSHA256, original, applied
        }

        public init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: Field.self)
            guard Set(fields.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)) else {
                throw Refusal.invalidRecord
            }
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decode(Int.self, forKey: .version)
            device = try values.decode(DeviceIdentity.self, forKey: .device)
            owner = try values.decode(Owner.self, forKey: .owner)
            effectiveConfigSHA256 = try values.decode(String.self, forKey: .effectiveConfigSHA256)
            original = try values.decode([Mapping].self, forKey: .original)
            applied = try values.decode([Mapping].self, forKey: .applied)
            try validateRecord(self)
        }
    }

    public static func acquire(original: [Mapping], device: DeviceIdentity, devices: [DeviceIdentity],
                               owner: Owner, effectiveConfigSHA256: String) throws -> Record
    {
        guard device.isValid else { throw Refusal.invalidDevice }
        // A merged monitor event cannot establish that there is exactly one instance.
        let matching = devices.filter { $0.registryEntryID == device.registryEntryID }
        guard matching == [device] else { throw Refusal.ambiguousDevice }
        // hidutil may match by this locator instead of registry ID. It must not
        // select a second event service even when registry IDs are distinct.
        let locatorMatches = devices.filter {
            $0.vendorID == device.vendorID && $0.productID == device.productID
                && (device.serialNumber == nil || $0.serialNumber == device.serialNumber)
                && (device.locationID == nil || $0.locationID == device.locationID)
        }
        guard locatorMatches == [device] else { throw Refusal.ambiguousDevice }
        guard owner.isValid else { throw Refusal.invalidOwner }
        guard validDigest(effectiveConfigSHA256) else { throw Refusal.invalidConfigDigest }
        try validateOriginal(original)
        return Record(device: device, owner: owner, effectiveConfigSHA256: effectiveConfigSHA256, original: original)
    }

    /// Returns the exact original array only when the same boot, device instance,
    /// and ordered applied array remain present. A refusal requires leaving state intact.
    /// hidutil has no proven compare-and-set: caller read/write races remain unsolved.
    /// An identical foreign replacement (ABA) cannot be distinguished from ours.
    public static func restore(record: Record, current: [Mapping], device: DeviceIdentity,
                               bootSessionUUID: String) throws -> [Mapping]
    {
        try validateRecord(record)
        guard bootSessionUUID == record.owner.bootSessionUUID else { throw Refusal.differentBoot }
        guard device == record.device else { throw Refusal.differentDevice }
        guard current == record.applied else { throw Refusal.foreignMapping }
        return record.original
    }

    private static func validateOriginal(_ mappings: [Mapping]) throws {
        var sources = Set<UInt64>()
        for mapping in mappings {
            guard Mapping.validUsage(mapping.source), Mapping.validUsage(mapping.destination) else {
                throw Refusal.malformedMapping
            }
            guard sources.insert(mapping.source).inserted else { throw Refusal.duplicateSource }
            guard mapping.source != caps else { throw Refusal.capsAlreadyMapped }
            guard mapping.source != f18, mapping.destination != f18 else { throw Refusal.f18Collision }
        }
    }

    private static func validateRecord(_ record: Record) throws {
        guard record.version == 1, record.device.isValid, record.owner.isValid,
              validDigest(record.effectiveConfigSHA256),
              record.applied == record.original + [Mapping(source: caps, destination: f18)]
        else {
            throw Refusal.invalidRecord
        }
        try validateOriginal(record.original)
    }

    private static func validDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48 ... 57).contains($0) || (97 ... 102).contains($0) }
    }

    private struct Field: CodingKey {
        let stringValue: String
        var intValue: Int? {
            nil
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            nil
        }
    }
}
