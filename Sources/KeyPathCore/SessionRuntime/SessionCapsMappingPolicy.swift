import Foundation

/// Pure decisions for one device-scoped Caps substitution. Transport and durable
/// intent/readback belong to the session lifecycle; this does not authorize writes.
public enum SessionCapsMappingPolicy {
    /// Packed keyboard-page usages, also exercised by caps-path-trial.py.
    public static let caps: UInt64 = 0x7_0000_0039
    /// The intermediate used before it became a choice; version-1 records imply it.
    public static let f18: UInt64 = 0x7_0000_006D

    /// Packed keyboard-page usage for an intermediate usage ID.
    public static func packed(_ usage: UInt32) -> UInt64 {
        0x7_0000_0000 | UInt64(usage)
    }

    public enum Refusal: Error, Equatable {
        case malformedMapping, duplicateSource, capsAlreadyMapped, intermediateCollision, invalidIntermediate
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
        /// Witnessed Apple built-in FIFO event service; zero VID/PID are legitimate.
        public let appleBuiltIn: Bool?

        public init(registryEntryID: UInt64, vendorID: UInt32, productID: UInt32,
                    serialNumber: String?, locationID: UInt32?, appleBuiltIn: Bool? = nil)
        {
            self.registryEntryID = registryEntryID
            self.vendorID = vendorID
            self.productID = productID
            self.serialNumber = serialNumber
            self.locationID = locationID
            self.appleBuiltIn = appleBuiltIn
        }

        fileprivate var isValid: Bool {
            registryEntryID != 0 && (vendorID != 0 || (appleBuiltIn == true && productID == 0 && (locationID ?? 0) != 0)) && vendorID <= 0xFFFF && productID <= 0xFFFF
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

    /// Another event service of the leased keyboard (a board can deliver its
    /// keys on several interfaces) and its mappings before the lease.
    public struct Companion: Codable, Sendable, Equatable {
        public let registryEntryID: UInt64
        public let original: [Mapping]

        public init(registryEntryID: UInt64, original: [Mapping]) {
            self.registryEntryID = registryEntryID
            self.original = original
        }
    }

    /// Persist before mutation, then independently verify `applied` before running.
    /// A record is intent, not proof that the mapping was written or that a PID lives.
    /// Version 2 names its intermediate; a version-1 record (written before
    /// the intermediate was a choice) has no such field and means F18.
    /// Version 3 also lists companion interfaces, each with its own original;
    /// a lease without companions is still written as version 2.
    public struct Record: Codable, Sendable, Equatable {
        public let version: Int
        public let device: DeviceIdentity
        public let owner: Owner
        public let effectiveConfigSHA256: String
        public let intermediate: UInt64
        public let original: [Mapping]
        public let applied: [Mapping]
        public let companions: [Companion]

        fileprivate init(device: DeviceIdentity, owner: Owner, effectiveConfigSHA256: String,
                         intermediate: UInt64, original: [Mapping], companions: [Companion])
        {
            version = companions.isEmpty ? 2 : 3
            self.device = device
            self.owner = owner
            self.effectiveConfigSHA256 = effectiveConfigSHA256
            self.intermediate = intermediate
            self.original = original
            self.companions = companions.sorted { $0.registryEntryID < $1.registryEntryID }
            applied = original + [Mapping(source: caps, destination: intermediate)]
        }

        /// What the lease writes over `original` on any of its services.
        public func applied(over original: [Mapping]) -> [Mapping] {
            original + [Mapping(source: caps, destination: intermediate)]
        }

        /// Every leased service with its original mappings, the chosen one first.
        public var originals: [(registryEntryID: UInt64, original: [Mapping])] {
            [(device.registryEntryID, original)] + companions.map { ($0.registryEntryID, $0.original) }
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case version, device, owner, effectiveConfigSHA256, intermediate, original, applied, companions
        }

        public init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: Field.self)
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decode(Int.self, forKey: .version)
            let expected = Set(CodingKeys.allCases.map(\.rawValue))
            let present = Set(fields.allKeys.map(\.stringValue))
            switch version {
            case 1: guard present == expected.subtracting([CodingKeys.intermediate.rawValue, CodingKeys.companions.rawValue]) else { throw Refusal.invalidRecord }
            case 2: guard present == expected.subtracting([CodingKeys.companions.rawValue]) else { throw Refusal.invalidRecord }
            case 3: guard present == expected else { throw Refusal.invalidRecord }
            default: throw Refusal.invalidRecord
            }
            device = try values.decode(DeviceIdentity.self, forKey: .device)
            owner = try values.decode(Owner.self, forKey: .owner)
            effectiveConfigSHA256 = try values.decode(String.self, forKey: .effectiveConfigSHA256)
            intermediate = version == 1 ? f18 : try values.decode(UInt64.self, forKey: .intermediate)
            original = try values.decode([Mapping].self, forKey: .original)
            applied = try values.decode([Mapping].self, forKey: .applied)
            companions = version == 3 ? try values.decode([Companion].self, forKey: .companions) : []
            try validateRecord(self)
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(version, forKey: .version)
            try values.encode(device, forKey: .device)
            try values.encode(owner, forKey: .owner)
            try values.encode(effectiveConfigSHA256, forKey: .effectiveConfigSHA256)
            if version != 1 { try values.encode(intermediate, forKey: .intermediate) }
            try values.encode(original, forKey: .original)
            try values.encode(applied, forKey: .applied)
            if version == 3 { try values.encode(companions, forKey: .companions) }
        }
    }

    /// The chosen keyboard must be connected exactly once, by registry ID and by
    /// the locator hidutil matches on. Other keyboards may be connected: the
    /// mapping is written only to this instance, and the intermediate is reserved for all.
    public static func requireUnique(_ device: DeviceIdentity, among devices: [DeviceIdentity]) throws {
        guard device.isValid else { throw Refusal.invalidDevice }
        // A merged monitor event cannot establish that there is exactly one instance.
        let matching = devices.filter { $0.registryEntryID == device.registryEntryID }
        guard matching == [device] else { throw Refusal.ambiguousDevice }
        // hidutil matches by this locator, not registry ID. The inventory lists
        // a multi-interface board once, so a second match here is a second
        // keyboard; the board's own other interfaces are the lease's companions.
        let locatorMatches = devices.filter {
            $0.vendorID == device.vendorID && $0.productID == device.productID
                && (device.serialNumber == nil || $0.serialNumber == device.serialNumber)
                && (device.locationID == nil || $0.locationID == device.locationID)
        }
        guard locatorMatches == [device] else { throw Refusal.ambiguousDevice }
    }

    /// `companions` are the keyboard's other keyboard-capable interfaces with
    /// their current mappings. Each is held to the same rules as `original`, so
    /// a Caps row on any interface refuses as `capsAlreadyMapped`.
    public static func acquire(original: [Mapping], device: DeviceIdentity, devices: [DeviceIdentity],
                               owner: Owner, effectiveConfigSHA256: String,
                               intermediate: UInt64 = f18, companions: [UInt64: [Mapping]] = [:]) throws -> Record
    {
        try requireUnique(device, among: devices)
        guard owner.isValid else { throw Refusal.invalidOwner }
        guard validDigest(effectiveConfigSHA256) else { throw Refusal.invalidConfigDigest }
        guard SessionCapsIntermediate.isCandidate(packed: intermediate) else { throw Refusal.invalidIntermediate }
        try validateOriginal(original, intermediate: intermediate)
        for mappings in companions.values {
            try validateOriginal(mappings, intermediate: intermediate)
        }
        let record = Record(device: device, owner: owner, effectiveConfigSHA256: effectiveConfigSHA256,
                            intermediate: intermediate, original: original,
                            companions: companions.map { Companion(registryEntryID: $0.key, original: $0.value) })
        try validateRecord(record)
        return record
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

    /// One leased service's original, when `current` is either that original
    /// or exactly what the lease applied there. Anything else is foreign and
    /// requires leaving every service intact.
    public static func restoreService(record: Record, registryEntryID: UInt64, current: [Mapping],
                                      bootSessionUUID: String) throws -> [Mapping]
    {
        try validateRecord(record)
        guard bootSessionUUID == record.owner.bootSessionUUID else { throw Refusal.differentBoot }
        guard let original = record.originals.first(where: { $0.registryEntryID == registryEntryID })?.original else {
            throw Refusal.differentDevice
        }
        guard current == original || current == record.applied(over: original) else { throw Refusal.foreignMapping }
        return original
    }

    private static func validateOriginal(_ mappings: [Mapping], intermediate: UInt64) throws {
        var sources = Set<UInt64>()
        for mapping in mappings {
            guard Mapping.validUsage(mapping.source), Mapping.validUsage(mapping.destination) else {
                throw Refusal.malformedMapping
            }
            guard sources.insert(mapping.source).inserted else { throw Refusal.duplicateSource }
            guard mapping.source != caps else { throw Refusal.capsAlreadyMapped }
            guard mapping.source != intermediate, mapping.destination != intermediate else { throw Refusal.intermediateCollision }
        }
    }

    private static func validateRecord(_ record: Record) throws {
        guard [1, 2, 3].contains(record.version), record.device.isValid, record.owner.isValid,
              validDigest(record.effectiveConfigSHA256),
              SessionCapsIntermediate.isCandidate(packed: record.intermediate),
              record.applied == record.original + [Mapping(source: caps, destination: record.intermediate)],
              (record.version == 3) == !record.companions.isEmpty, record.companions.count <= 16,
              Set(record.companions.map(\.registryEntryID)).count == record.companions.count,
              record.companions.allSatisfy({ $0.registryEntryID != 0 && $0.registryEntryID != record.device.registryEntryID })
        else {
            throw Refusal.invalidRecord
        }
        try validateOriginal(record.original, intermediate: record.intermediate)
        for companion in record.companions {
            try validateOriginal(companion.original, intermediate: record.intermediate)
        }
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
