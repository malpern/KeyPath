import Darwin
import Foundation
import IOKit
import KeyPathCore

/// Only the property output grammar witnessed in the owned physical-fixture
/// guest is accepted. IOHIDDevice registry IDs never stand in for event-service IDs.
public enum SessionCapsHIDUtilTransport {
    public enum Refusal: Error { case unsupportedOutput, commandFailed, timedOut, excessiveOutput }
    public typealias Policy = SessionCapsMappingPolicy

    public static func selector(_ device: Policy.DeviceIdentity) throws -> String {
        try selector(device, primaryUsagePage: 1, primaryUsage: 6)
    }

    /// One primary-usage pair of the chosen physical keyboard. hidutil cannot
    /// address a service by registry ID, so a keyboard whose keys also arrive
    /// on another interface (QMK's shared NKRO interface is mouse-primary) is
    /// reached by one selector per pair; see `serviceGroup`.
    public static func selector(_ device: Policy.DeviceIdentity, primaryUsagePage: UInt32, primaryUsage: UInt32) throws -> String {
        var match = try locatorMatch(device)
        match["PrimaryUsagePage"] = primaryUsagePage
        match["PrimaryUsage"] = primaryUsage
        return try String(decoding: JSONSerialization.data(withJSONObject: match, options: [.sortedKeys]), as: UTF8.self)
    }

    /// Every service of the chosen physical keyboard, whatever its usage.
    public static func locatorSelector(_ device: Policy.DeviceIdentity) throws -> String {
        try String(decoding: JSONSerialization.data(withJSONObject: locatorMatch(device), options: [.sortedKeys]), as: UTF8.self)
    }

    private static func locatorMatch(_ device: Policy.DeviceIdentity) throws -> [String: Any] {
        guard device.registryEntryID != 0, device.vendorID != 0 || (device.appleBuiltIn == true && device.productID == 0 && (device.locationID ?? 0) != 0), device.vendorID <= 0xFFFF,
              device.productID <= 0xFFFF, (device.locationID ?? 0) != 0 || device.serialNumber != nil else { throw Policy.Refusal.invalidDevice }
        if let serial = device.serialNumber {
            guard !serial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, serial.utf8.count <= 1024 else { throw Policy.Refusal.invalidDevice }
        }
        var match: [String: Any] = ["VendorID": device.vendorID, "ProductID": device.productID]
        if let location = device.locationID { match["LocationID"] = location }
        // SerialNumber is not a supported top-level matching key in hidutil help.
        if let serial = device.serialNumber { match["IOPropertyMatch"] = ["SerialNumber": serial] }
        return match
    }

    /// These arguments are for Process(executableURL: /usr/bin/hidutil), never a shell.
    public static func readArguments(_ device: Policy.DeviceIdentity) throws -> [String] {
        try ["property", "--matching", selector(device), "--get", "UserKeyMapping"]
    }

    public static func writeArguments(_ device: Policy.DeviceIdentity, mappings: [Policy.Mapping]) throws -> [String] {
        let rows = try JSONEncoder().encode(mappings)
        let json = "{\"UserKeyMapping\":" + String(decoding: rows, as: UTF8.self) + "}"
        return try ["property", "--matching", selector(device), "--set", json]
    }

    public static func parseProperty(_ output: String, device: Policy.DeviceIdentity) throws -> SessionCapsMappingLease.Snapshot {
        guard output.utf8.count <= 65536 else { throw Refusal.unsupportedOutput }
        let scanner = Scanner(string: output)
        scanner.charactersToBeSkipped = .whitespacesAndNewlines
        func token(_ value: String) throws {
            guard scanner.scanString(value) != nil else { throw Refusal.unsupportedOutput }
        }
        try token("RegistryID"); try token("Key"); try token("Value")
        guard let rawID = scanner.scanCharacters(from: CharacterSet(charactersIn: "0123456789abcdefABCDEF")),
              let id = UInt64(rawID, radix: 16), id == device.registryEntryID else { throw Refusal.unsupportedOutput }
        try token("UserKeyMapping"); try token("(")
        // A witnessed (null) is the effective empty mapping. Restoring [] has
        // the same mapping semantics; we do not claim literal nil restoration.
        if scanner.scanString("null") != nil {
            try token(")")
            guard scanner.isAtEnd else { throw Refusal.unsupportedOutput }
            return .init(device: device, mappings: [])
        }
        var mappings: [Policy.Mapping] = []
        if scanner.scanString(")") == nil {
            while true {
                try token("{")
                var row: [String: UInt64] = [:]
                for _ in 0 ..< 2 {
                    guard let key = scanner.scanCharacters(from: .letters),
                          ["HIDKeyboardModifierMappingSrc", "HIDKeyboardModifierMappingDst"].contains(key),
                          row[key] == nil else { throw Refusal.unsupportedOutput }
                    try token("=")
                    guard let decimal = scanner.scanCharacters(from: CharacterSet(charactersIn: "0123456789")),
                          let number = UInt64(decimal) else { throw Refusal.unsupportedOutput }
                    row[key] = number
                    try token(";")
                }
                try token("}")
                // The policy's decoder rejects invalid usage values and unknown
                // fields. No row is silently discarded or normalized.
                let data = try JSONSerialization.data(withJSONObject: row)
                try mappings.append(JSONDecoder().decode(Policy.Mapping.self, from: data))
                if scanner.scanString(")") != nil { break }
                try token(",")
            }
        }
        guard scanner.isAtEnd else { throw Refusal.unsupportedOutput }
        return .init(device: device, mappings: mappings)
    }

    /// Every service's UserKeyMapping from one unscoped `hidutil property
    /// --get UserKeyMapping`, keyed by registry ID. Each block uses the same
    /// grammar as `parseProperty`; any block that breaks it refuses the whole
    /// read, so an unreadable row is never mistaken for a free key.
    public static func parseAllMappings(_ output: String) throws -> [UInt64: [Policy.Mapping]] {
        guard output.utf8.count <= 1_048_576 else { throw Refusal.excessiveOutput }
        var lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let header = lines.first,
              header.split(whereSeparator: \.isWhitespace) == ["RegistryID", "Key", "Value"] else { throw Refusal.unsupportedOutput }
        lines.removeFirst()
        var result: [UInt64: [Policy.Mapping]] = [:]
        var current: (id: UInt64, text: String)?
        func finish() throws {
            guard let block = current else { return }
            let device = Policy.DeviceIdentity(registryEntryID: block.id, vendorID: 0, productID: 0, serialNumber: nil, locationID: nil)
            guard result[block.id] == nil else { throw Refusal.unsupportedOutput }
            result[block.id] = try parseProperty(header + "\n" + block.text, device: device).mappings
        }
        for line in lines {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count >= 3, fields[1] == "UserKeyMapping", let id = UInt64(fields[0], radix: 16), !line.hasPrefix(" ") {
                try finish()
                current = (id, line)
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            } else {
                guard current != nil else { throw Refusal.unsupportedOutput }
                current!.text += "\n" + line
            }
        }
        try finish()
        return result
    }

    /// Keyboard services from one `hidutil list`. `devices` are the instances a
    /// lease may target. `withheld` counts other physical keyboards (distinct
    /// LocationIDs, so a multi-interface board counts once): ones whose
    /// shape is not supported, or whose locator would also select another
    /// service. They are never targets, but they mean "exactly one keyboard"
    /// cannot be assumed. Virtual services without a location (Karabiner's
    /// DriverKit keyboard, the Parallels platform keyboard) are ignored.
    public struct Inventory: Sendable, Equatable {
        public let devices: [Policy.DeviceIdentity]
        public let withheld: Int
    }

    public static func parseServices(_ ndjson: String) throws -> [Policy.DeviceIdentity] {
        try parseInventory(ndjson).devices
    }

    /// Output that breaks the witnessed grammar still refuses the whole list.
    /// A well-formed service that cannot be a target is skipped by itself, so
    /// one odd keyboard no longer hides every other one.
    public static func parseInventory(_ ndjson: String) throws -> Inventory {
        guard ndjson.utf8.count <= 65536 else { throw Refusal.excessiveOutput }
        struct Locator { let registry: UInt64?; let vendor: UInt64?; let product: UInt64?; let location: UInt64; let serial: String? }
        var candidates: [Policy.DeviceIdentity] = []
        var others: [Locator] = []
        for line in ndjson.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            guard let row = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = row["type"] as? String, ["service", "device"].contains(type) else { throw Refusal.unsupportedOutput }
            if type == "device" { continue }
            func optional(_ key: String, maximum: UInt64 = UInt64.max) throws -> UInt64? {
                guard let raw = row[key] else { return nil }
                // JSON booleans and floats bridge through NSNumber too. Check
                // their concrete representation before accepting an integer.
                guard let value = raw as? NSNumber,
                      String(cString: value.objCType) != "c",
                      !["f", "d"].contains(String(cString: value.objCType)),
                      let integer = UInt64(value.stringValue), integer <= maximum else { throw Refusal.unsupportedOutput }
                return integer
            }
            func number(_ key: String, maximum: UInt64 = UInt64.max) throws -> UInt64 {
                guard let value = try optional(key, maximum: maximum) else { throw Refusal.unsupportedOutput }
                return value
            }
            let page = try number("PrimaryUsagePage", maximum: 0xFFFF)
            let usage = try number("PrimaryUsage", maximum: 0xFFFF)
            if page != 1 || usage != 6 { continue }
            let registry = try optional("IORegistryEntryID")
            let vendor = try optional("VendorID", maximum: 0xFFFF)
            let product = try optional("ProductID", maximum: 0xFFFF)
            // Every target selector carries a nonzero LocationID, so a service
            // without one can never be written by a lease. Witnessed: Karabiner
            // VirtualHIDKeyboard (AppleUserHIDEventService, no Transport) and the
            // Parallels AppleVirtualPlatformHIDBridge keyboard, both LocationID 0.
            guard let location = try optional("LocationID", maximum: UInt64(UInt32.max)), location != 0 else { continue }
            // A blank or odd serial cannot corroborate an instance. That service
            // is withheld with no serial, so it shadows every same-locator target.
            var serial: String?
            var serialUsable = true
            if let value = row["SerialNumber"] {
                if let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   string.utf8.count <= 1024 { serial = string } else { serialUsable = false }
            }
            let ioClass = row["IOClass"] as? String
            let appleBuiltIn = ioClass == "AppleHIDKeyboardEventDriverV2" && row["Built-In"] as? Bool == true && row["Transport"] as? String == "FIFO"
            guard serialUsable, ioClass == "AppleUserHIDEventService" || appleBuiltIn,
                  let registry, registry != 0, let vendor, let product,
                  vendor != 0 || (appleBuiltIn && product == 0)
            else {
                // A located keyboard of an unsupported shape. Keep its locator:
                // a target sharing it would have the mapping written here too.
                others.append(Locator(registry: registry, vendor: vendor, product: product, location: location, serial: serial))
                continue
            }
            candidates.append(Policy.DeviceIdentity(registryEntryID: registry, vendorID: UInt32(vendor),
                                                    productID: UInt32(product), serialNumber: serial,
                                                    locationID: UInt32(location), appleBuiltIn: appleBuiltIn ? true : nil))
        }
        let locators = candidates.map {
            Locator(registry: $0.registryEntryID, vendor: UInt64($0.vendorID), product: UInt64($0.productID),
                    location: UInt64($0.locationID ?? 0), serial: $0.serialNumber)
        }
        /// A service whose registry ID or hidutil locator is shared cannot be
        /// addressed alone (for example one keyboard exposing two keyboard
        /// interfaces). Every sharer is withheld; none is chosen arbitrarily.
        func collides(_ a: Locator, _ b: Locator) -> Bool {
            if let id = a.registry, id == b.registry { return true }
            return a.vendor != nil && a.vendor == b.vendor && a.product != nil && a.product == b.product && a.location == b.location
                && (a.serial == nil || b.serial == nil || a.serial == b.serial)
        }
        /// A LocationID names one USB device, so keyboard services with the same
        /// VID/PID/LocationID and serial are interfaces of one physical keyboard,
        /// not twins. It is listed once, by its lowest registry ID, and the lease
        /// covers every interface (`serviceGroup`). Any other overlap is withheld.
        func sameKeyboard(_ a: Locator, _ b: Locator) -> Bool {
            a.registry != b.registry && a.vendor == b.vendor && a.product == b.product
                && a.location == b.location && a.serial == b.serial
        }
        var devices: [Policy.DeviceIdentity] = []
        // Count keyboards, not services: interfaces of one board share a LocationID.
        var withheld = Set(others.map(\.location))
        for (index, device) in candidates.enumerated() {
            let peers = locators.indices.filter { $0 != index && collides(locators[index], locators[$0]) }
            let ambiguous = others.contains { collides(locators[index], $0) }
                || !peers.allSatisfy { sameKeyboard(locators[index], locators[$0]) }
            if ambiguous {
                withheld.insert(locators[index].location)
            } else if peers.allSatisfy({ (locators[$0].registry ?? 0) > device.registryEntryID }) {
                devices.append(device)
            }
        }
        return Inventory(devices: devices, withheld: withheld.count)
    }

    /// One event service of an unfiltered `hidutil list`, as grouping needs it.
    public struct ServiceRow: Sendable, Equatable {
        public let registryEntryID: UInt64
        public let vendorID: UInt32
        public let productID: UInt32
        public let locationID: UInt32?
        public let serialNumber: String?
        public let primaryUsagePage: UInt32
        public let primaryUsage: UInt32
    }

    /// Service rows only; device rows and services missing an identity field
    /// are skipped. Output that breaks the JSON grammar refuses.
    public static func parseServiceRows(_ ndjson: String) throws -> [ServiceRow] {
        guard ndjson.utf8.count <= 65536 else { throw Refusal.excessiveOutput }
        var rows: [ServiceRow] = []
        for line in ndjson.split(separator: "\n") where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let row = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = row["type"] as? String else { throw Refusal.unsupportedOutput }
            guard type == "service" else { continue }
            func integer(_ key: String, maximum: UInt64) -> UInt64? {
                guard let value = row[key] as? NSNumber, String(cString: value.objCType) != "c",
                      !["f", "d"].contains(String(cString: value.objCType)),
                      let number = UInt64(value.stringValue), number <= maximum else { return nil }
                return number
            }
            guard let registry = integer("IORegistryEntryID", maximum: .max), registry != 0,
                  let vendor = integer("VendorID", maximum: 0xFFFF), let product = integer("ProductID", maximum: 0xFFFF),
                  let page = integer("PrimaryUsagePage", maximum: 0xFFFF), let usage = integer("PrimaryUsage", maximum: 0xFFFF)
            else { continue }
            let location = integer("LocationID", maximum: UInt64(UInt32.max)).map(UInt32.init)
            rows.append(ServiceRow(registryEntryID: registry, vendorID: UInt32(vendor), productID: UInt32(product),
                                   locationID: location, serialNumber: row["SerialNumber"] as? String,
                                   primaryUsagePage: UInt32(page), primaryUsage: UInt32(usage)))
        }
        return rows
    }

    /// True when a HID report descriptor declares an Input item while the
    /// Keyboard/Keypad page (0x07) is the current usage page. LED outputs
    /// (page 0x08) and keyboard pages inside a feature report do not count.
    public static func descriptorHasKeyboardInput(_ bytes: [UInt8]) -> Bool {
        var page: UInt32 = 0
        var stack: [UInt32] = []
        var index = 0
        while index < bytes.count {
            let prefix = bytes[index]
            if prefix == 0xFE { // Long item: data size in the next byte.
                guard index + 1 < bytes.count else { return false }
                index += 3 + Int(bytes[index + 1])
                continue
            }
            let size = [0, 1, 2, 4][Int(prefix & 0x03)]
            guard index + size < bytes.count else { return false }
            var value: UInt32 = 0
            for offset in 0 ..< size {
                value |= UInt32(bytes[index + 1 + offset]) << (8 * offset)
            }
            switch prefix & 0xFC {
            case 0x04: page = value // Usage Page (global)
            case 0xA4: stack.append(page) // Push
            case 0xB4: page = stack.popLast() ?? page // Pop
            case 0x80: if page == 0x07 { return true } // Input (main)
            default: break
            }
            index += 1 + size
        }
        return false
    }

    /// Whether an event service can emit keyboard usages: a top-level Keyboard
    /// collection in its DeviceUsagePairs, or keyboard-page inputs in its
    /// device's report descriptor. nil when neither property is readable.
    public static func serviceEmitsKeyboardUsages(_ registryEntryID: UInt64) -> Bool? {
        guard registryEntryID != 0, let matching = IORegistryEntryIDMatching(registryEntryID) else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var readable = false
        if let pairs = IORegistryEntryCreateCFProperty(service, "DeviceUsagePairs" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]]
        {
            readable = true
            if pairs.contains(where: { ($0["DeviceUsagePage"] as? NSNumber)?.intValue == 1 && ($0["DeviceUsage"] as? NSNumber)?.intValue == 6 }) {
                return true
            }
        }
        if let descriptor = IORegistryEntrySearchCFProperty(service, "IOService", "ReportDescriptor" as CFString, kCFAllocatorDefault,
                                                            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? Data
        {
            return descriptorHasKeyboardInput([UInt8](descriptor))
        }
        return readable ? false : nil
    }

    /// The chosen keyboard's event services: the leased service plus every
    /// other service of the same physical device that can emit keyboard usages.
    /// A board in NKRO mode sends every key, Caps included, on such an
    /// interface; mapping only the boot interface leaves Caps native there.
    public struct ServiceGroup: Sendable, Equatable {
        public let anchor: UInt64
        public let members: Set<UInt64>
        /// Primary-usage pairs to address, anchor's first.
        public let pairs: [[UInt32]]
    }

    public static func serviceGroup(for device: Policy.DeviceIdentity, rows: [ServiceRow],
                                    emitsKeyboardUsages: (UInt64) -> Bool?) throws -> ServiceGroup
    {
        let local = rows.filter {
            $0.vendorID == device.vendorID && $0.productID == device.productID && $0.locationID == device.locationID
                && (device.serialNumber == nil || $0.serialNumber == device.serialNumber)
        }
        guard let anchor = local.first(where: { $0.registryEntryID == device.registryEntryID }) else {
            throw Policy.Refusal.differentDevice
        }
        let anchorPair = [anchor.primaryUsagePage, anchor.primaryUsage]
        var pairs = [anchorPair]
        for row in local where row.registryEntryID != anchor.registryEntryID {
            let pair = [row.primaryUsagePage, row.primaryUsage]
            if !pairs.contains(pair), emitsKeyboardUsages(row.registryEntryID) == true { pairs.append(pair) }
        }
        // Every service a selector reaches is a member, whether or not it can
        // emit Caps itself, so read-back and restoration cover all of them.
        let members = Set(local.filter { pairs.contains([$0.primaryUsagePage, $0.primaryUsage]) }.map(\.registryEntryID))
        return ServiceGroup(anchor: anchor.registryEntryID, members: members, pairs: pairs)
    }

    static func groupMappings(_ device: Policy.DeviceIdentity, _ group: ServiceGroup,
                              run: ([String]) throws -> String) throws -> [UInt64: [Policy.Mapping]]
    {
        var result: [UInt64: [Policy.Mapping]] = [:]
        for pair in group.pairs {
            let selector = try selector(device, primaryUsagePage: pair[0], primaryUsage: pair[1])
            for (id, mappings) in try parseAllMappings(run(["property", "--matching", selector, "--get", "UserKeyMapping"])) {
                guard result.updateValue(mappings, forKey: id) == nil else { throw Refusal.unsupportedOutput }
            }
        }
        guard Set(result.keys) == group.members else { throw Policy.Refusal.differentDevice }
        return result
    }

    static func writeGroup(_ device: Policy.DeviceIdentity, _ group: ServiceGroup, mappings: [Policy.Mapping],
                           run: ([String]) throws -> String) throws
    {
        let rows = try JSONEncoder().encode(mappings)
        let json = "{\"UserKeyMapping\":" + String(decoding: rows, as: UTF8.self) + "}"
        var written = Set<UInt64>()
        // Every pair is attempted before refusing, so a partial failure leaves
        // as few interfaces behind as possible; restore handles any mixture.
        var failure: Error?
        for pair in group.pairs {
            do {
                let selector = try selector(device, primaryUsagePage: pair[0], primaryUsage: pair[1])
                for (id, readback) in try parseAllMappings(run(["property", "--matching", selector, "--set", json])) {
                    guard readback == mappings else { throw SessionCapsMappingLease.Refusal.unverifiedWrite }
                    written.insert(id)
                }
            } catch { failure = failure ?? error }
        }
        if let failure { throw failure }
        guard written == group.members else { throw SessionCapsMappingLease.Refusal.unverifiedWrite }
    }

    /// One compatible keyboard with its display name. The name is for the
    /// picker only: it is never persisted or used to identify the device.
    public struct Keyboard: Sendable, Equatable, Identifiable {
        public let device: Policy.DeviceIdentity
        public let name: String
        public var id: UInt64 {
            device.registryEntryID
        }
    }

    /// Eligibility comes from `parseServices`; names are a best-effort overlay
    /// keyed by registry ID, so a missing or odd name never admits a device.
    public static func parseKeyboards(_ ndjson: String) throws -> [Keyboard] {
        try parseKeyboardList(ndjson).keyboards
    }

    /// Named targets plus the count of physical keyboards that cannot be one.
    public static func parseKeyboardList(_ ndjson: String) throws -> (keyboards: [Keyboard], withheld: Int) {
        let inventory = try parseInventory(ndjson)
        let devices = inventory.devices
        var names: [UInt64: String] = [:]
        for line in ndjson.split(separator: "\n") {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  row["type"] as? String == "service",
                  let id = (row["IORegistryEntryID"] as? NSNumber).flatMap({ UInt64($0.stringValue) }),
                  let product = row["Product"] as? String else { continue }
            let trimmed = product.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed.utf8.count <= 256 { names[id] = trimmed }
        }
        let base = devices.map { device in
            device.appleBuiltIn == true ? "Built-in keyboard" : names[device.registryEntryID] ?? "Keyboard"
        }
        // Two identical keyboards share a product name; number them in list order.
        var seen: [String: Int] = [:]
        let keyboards = zip(devices, base).map { device, name in
            guard base.count(where: { $0 == name }) > 1 else { return Keyboard(device: device, name: name) }
            seen[name, default: 0] += 1
            return Keyboard(device: device, name: "\(name) \(seen[name]!)")
        }
        return (keyboards, inventory.withheld)
    }

    /// Synchronous; call off the main actor.
    public static func keyboards(run: ([String]) throws -> String = runHIDUtil) throws -> (keyboards: [Keyboard], withheld: Int) {
        try parseKeyboardList(run(["list", "--ndjson", "--matching", "keyboard"]))
    }

    /// Synchronous; call off the main actor.
    public static func inventory(run: ([String]) throws -> String = runHIDUtil) throws -> Inventory {
        try parseInventory(run(["list", "--ndjson", "--matching", "keyboard"]))
    }

    /// Query the exact ID without keyboard eligibility filters. The fast match
    /// finds registered services; before claiming absence, inspect the registry
    /// plane too because an unregistered service can still be present there.
    public static func registryEntryExists(_ registryEntryID: UInt64) throws -> Bool {
        guard registryEntryID != 0,
              let matching = IORegistryEntryIDMatching(registryEntryID) else { throw Refusal.commandFailed }
        var matches: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &matches) == KERN_SUCCESS else {
            throw Refusal.commandFailed
        }
        if matches != 0 {
            defer { IOObjectRelease(matches) }
            let service = IOIteratorNext(matches)
            if service != 0 {
                IOObjectRelease(service)
                return true
            }
            guard IOIteratorIsValid(matches) != 0 else { throw Refusal.commandFailed }
        }
        // A successful match may return a null iterator for no registered match.
        var entries: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane,
                                       IOOptionBits(kIORegistryIterateRecursively), &entries) == KERN_SUCCESS,
            entries != 0 else { throw Refusal.commandFailed }
        defer { IOObjectRelease(entries) }
        while true {
            let entry = IOIteratorNext(entries)
            guard entry != 0 else { break }
            var currentID: UInt64 = 0
            let result = IORegistryEntryGetRegistryEntryID(entry, &currentID)
            IOObjectRelease(entry)
            guard result == KERN_SUCCESS else { throw Refusal.commandFailed }
            if currentID == registryEntryID { return true }
        }
        guard IOIteratorIsValid(entries) != 0 else { throw Refusal.commandFailed }
        return false
    }

    /// Injected execution keeps focused tests entirely off host HID state.
    /// The real runner is synchronous and must be called off the main actor.
    /// Reads and writes cover the chosen keyboard's whole `serviceGroup`. A
    /// read whose interfaces disagree refuses; `readGroup` exposes them for restore.
    public static func backend(run: @escaping ([String]) throws -> String = runHIDUtil,
                               emitsKeyboardUsages: @escaping (UInt64) -> Bool? = serviceEmitsKeyboardUsages) -> SessionCapsMappingLease.Backend
    {
        func group(_ device: Policy.DeviceIdentity) throws -> ServiceGroup {
            try serviceGroup(for: device, rows: parseServiceRows(run(["list", "--ndjson", "--matching", locatorSelector(device)])),
                             emitsKeyboardUsages: emitsKeyboardUsages)
        }
        func readAll(_ device: Policy.DeviceIdentity) throws -> [UInt64: [Policy.Mapping]] {
            try groupMappings(device, group(device), run: run)
        }
        return .init(enumerate: { try parseServices(run(["list", "--ndjson", "--matching", "keyboard"])) },
                     read: { device in
                         let all = try readAll(device)
                         guard let anchor = all[device.registryEntryID] else { throw Policy.Refusal.differentDevice }
                         guard all.values.allSatisfy({ $0 == anchor }) else { throw Policy.Refusal.foreignMapping }
                         return .init(device: device, mappings: anchor)
                     },
                     write: { device, mappings in try writeGroup(device, group(device), mappings: mappings, run: run) },
                     registryEntryExists: registryEntryExists,
                     readGroup: readAll)
    }

    #if DEBUG
        /// Real hidutil is queued but has executed no user code. Root may resume the orphan later.
        /// Does not claim death inside an opaque HID mutation call; never used for restore/read.
        static func terminateOwnerWithSuspendedWriter(record: Policy.Record, mappings: [Policy.Mapping],
                                                      publishCheckpoint: (Int32) throws -> Void) throws -> Never
        {
            guard SessionCapsMappingLease.terminateWithQueuedWriter(record: record, mappings: mappings) else {
                throw SessionCapsMappingLease.Refusal.mutationUncertain
            }
            var actions: posix_spawn_file_actions_t?
            guard posix_spawn_file_actions_init(&actions) == 0 else { throw Refusal.commandFailed }
            defer { posix_spawn_file_actions_destroy(&actions) }
            for descriptor in 0 ... 2 {
                guard posix_spawn_file_actions_addopen(&actions, Int32(descriptor), "/dev/null", O_RDWR, 0) == 0 else {
                    throw Refusal.commandFailed
                }
            }
            var attributes: posix_spawnattr_t?
            guard posix_spawnattr_init(&attributes) == 0 else { throw Refusal.commandFailed }
            defer { posix_spawnattr_destroy(&attributes) }
            // A stopped child in the worker's group receives HUP/CONT when that
            // group becomes orphaned. SETSID isolates this DEBUG checkpoint from
            // that group; actual HID child survival still needs live verification.
            // macOS27 SDK: START_SUSPENDED=0x0080, SETSID=0x0400, CLOEXEC_DEFAULT=0x4000.
            guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_START_SUSPENDED | POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT)) == 0 else {
                throw Refusal.commandFailed
            }
            let arguments = try ["/usr/bin/hidutil"] + writeArguments(record.device, mappings: mappings)
            let strings = arguments.map { strdup($0) }
            defer { strings.forEach { free($0) } }
            guard strings.allSatisfy({ $0 != nil }) else { throw Refusal.commandFailed }
            var argv = strings + [nil]
            var childPID: pid_t = 0
            var emptyEnvironment: [UnsafeMutablePointer<CChar>?] = [nil]
            let spawned = argv.withUnsafeMutableBufferPointer { buffer in
                emptyEnvironment.withUnsafeMutableBufferPointer { environment in
                    posix_spawn(&childPID, "/usr/bin/hidutil", &actions, &attributes, buffer.baseAddress!, environment.baseAddress!)
                }
            }
            guard spawned == 0, childPID > 0 else { throw Refusal.commandFailed }
            // An unreaped child PID cannot be reused. Never signal after observing it reaped.
            var unreaped = true
            defer {
                if unreaped {
                    _ = Darwin.kill(childPID, SIGKILL)
                    var status: Int32 = 0
                    while waitpid(childPID, &status, 0) < 0, errno == EINTR {}
                }
            }
            var status: Int32 = 0
            var observed: pid_t
            repeat {
                observed = waitpid(childPID, &status, WNOHANG)
            } while observed < 0 && errno == EINTR
            guard observed == 0 else {
                if observed == childPID || (observed < 0 && errno == ECHILD) { unreaped = false }
                throw Refusal.commandFailed
            }
            try publishCheckpoint(childPID)
            Darwin.kill(getpid(), SIGKILL)
            // Signal delivery may race another thread. Never unwind the child-cleanup
            // defer after publishing its handoff; publication failures still clean up.
            Darwin._exit(128 + SIGKILL)
        }
    #endif

    public static func runHIDUtil(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let output = Pipe(), error = Pipe()
        process.standardOutput = output
        process.standardError = error
        let handles = [output.fileHandleForReading, error.fileHandleForReading]
        defer { for handle in handles {
            try? handle.close()
        } }
        for handle in handles {
            guard fcntl(handle.fileDescriptor, F_SETFL, O_NONBLOCK) == 0 else { throw Refusal.commandFailed }
        }
        let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        try process.run()
        try? output.fileHandleForWriting.close()
        try? error.fileHandleForWriting.close()
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            // Confirm exit before the caller releases its mapping lock. A
            // deadline bounds useful work, not kernel termination latency.
            process.waitUntilExit()
        }
        var data = [Data(), Data()]
        var ended = [false, false]
        var buffer = [UInt8](repeating: 0, count: 4096)
        while process.isRunning || !ended.allSatisfy({ $0 }) {
            guard DispatchTime.now().uptimeNanoseconds < deadline else { throw Refusal.timedOut }
            for index in 0 ..< handles.count where !ended[index] {
                let count = Darwin.read(handles[index].fileDescriptor, &buffer, buffer.count)
                if count > 0 {
                    data[index].append(contentsOf: buffer.prefix(count))
                    guard data[0].count + data[1].count <= 65536 else { throw Refusal.excessiveOutput }
                } else if count == 0 { ended[index] = true }
                else if errno != EAGAIN, errno != EINTR { throw Refusal.commandFailed }
            }
            var descriptors = handles.enumerated().map { index, handle in
                pollfd(fd: ended[index] ? -1 : handle.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            }
            _ = poll(&descriptors, nfds_t(descriptors.count), 10)
        }
        guard process.terminationStatus == 0, data[1].isEmpty,
              let text = String(data: data[0], encoding: .utf8) else { throw Refusal.commandFailed }
        return text
    }
}
