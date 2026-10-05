import Darwin
import Foundation
import KeyPathCore

/// Only the property output grammar witnessed in the owned physical-fixture
/// guest is accepted. IOHIDDevice registry IDs never stand in for event-service IDs.
public enum SessionCapsHIDUtilTransport {
    public enum Refusal: Error { case unsupportedOutput, commandFailed, timedOut, excessiveOutput }
    public typealias Policy = SessionCapsMappingPolicy

    public static func selector(_ device: Policy.DeviceIdentity) throws -> String {
        guard device.registryEntryID != 0, device.vendorID != 0, device.vendorID <= 0xFFFF,
              device.productID <= 0xFFFF, (device.locationID ?? 0) != 0 || device.serialNumber != nil else { throw Policy.Refusal.invalidDevice }
        if let serial = device.serialNumber {
            guard !serial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, serial.utf8.count <= 1024 else { throw Policy.Refusal.invalidDevice }
        }
        var match: [String: Any] = ["VendorID": device.vendorID, "ProductID": device.productID,
                                    "PrimaryUsagePage": 1, "PrimaryUsage": 6]
        if let location = device.locationID { match["LocationID"] = location }
        // SerialNumber is not a supported top-level matching key in hidutil help.
        if let serial = device.serialNumber { match["IOPropertyMatch"] = ["SerialNumber": serial] }
        return String(decoding: try JSONSerialization.data(withJSONObject: match, options: [.sortedKeys]), as: UTF8.self)
    }

    /// These arguments are for Process(executableURL: /usr/bin/hidutil), never a shell.
    public static func readArguments(_ device: Policy.DeviceIdentity) throws -> [String] {
        ["property", "--matching", try selector(device), "--get", "UserKeyMapping"]
    }
    public static func writeArguments(_ device: Policy.DeviceIdentity, mappings: [Policy.Mapping]) throws -> [String] {
        let rows = try JSONEncoder().encode(mappings)
        let json = "{\"UserKeyMapping\":" + String(decoding: rows, as: UTF8.self) + "}"
        return ["property", "--matching", try selector(device), "--set", json]
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
                mappings.append(try JSONDecoder().decode(Policy.Mapping.self, from: data))
                if scanner.scanString(")") != nil { break }
                try token(",")
            }
        }
        guard scanner.isAtEnd else { throw Refusal.unsupportedOutput }
        return .init(device: device, mappings: mappings)
    }

    public static func parseServices(_ ndjson: String) throws -> [Policy.DeviceIdentity] {
        guard ndjson.utf8.count <= 65536 else { throw Refusal.excessiveOutput }
        var devices: [Policy.DeviceIdentity] = []
        for line in ndjson.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            guard let row = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = row["type"] as? String, ["service", "device"].contains(type) else { throw Refusal.unsupportedOutput }
            if type == "device" { continue }
            func number(_ key: String, maximum: UInt64 = UInt64.max) throws -> UInt64 {
                // JSON booleans and floats bridge through NSNumber too. Check
                // their concrete representation before accepting an integer.
                guard let value = row[key] as? NSNumber,
                      String(cString: value.objCType) != "c",
                      !["f", "d"].contains(String(cString: value.objCType)),
                      let integer = UInt64(value.stringValue), integer <= maximum else { throw Refusal.unsupportedOutput }
                return integer
            }
            let page = try number("PrimaryUsagePage", maximum: 0xFFFF)
            let usage = try number("PrimaryUsage", maximum: 0xFFFF)
            guard let ioClass = row["IOClass"] as? String, !ioClass.isEmpty else { throw Refusal.unsupportedOutput }
            if page != 1 || usage != 6 { continue }
            guard ioClass == "AppleUserHIDEventService" else { throw Refusal.unsupportedOutput }
            let registry = try number("IORegistryEntryID")
            let vendor = try number("VendorID", maximum: 0xFFFF)
            let product = try number("ProductID", maximum: 0xFFFF)
            let location = try number("LocationID", maximum: UInt64(UInt32.max))
            guard registry != 0, vendor != 0, location != 0 else { throw Refusal.unsupportedOutput }
            var serial: String?
            if let value = row["SerialNumber"] {
                guard let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      string.utf8.count <= 1024 else { throw Refusal.unsupportedOutput }
                serial = string
            }
            let device = Policy.DeviceIdentity(registryEntryID: registry, vendorID: UInt32(vendor),
                                               productID: UInt32(product), serialNumber: serial, locationID: UInt32(location))
            guard !devices.contains(where: { $0.registryEntryID == registry ||
                ($0.vendorID == device.vendorID && $0.productID == device.productID && $0.locationID == device.locationID &&
                    ($0.serialNumber == nil || device.serialNumber == nil || $0.serialNumber == device.serialNumber))
            }) else { throw Policy.Refusal.ambiguousDevice }
            devices.append(device)
        }
        return devices
    }

    /// Injected execution keeps focused tests entirely off host HID state.
    /// The real runner is synchronous and must be called off the main actor.
    public static func backend(run: @escaping ([String]) throws -> String = runHIDUtil) -> SessionCapsMappingLease.Backend {
        .init(enumerate: { try parseServices(run(["list", "--ndjson", "--matching", "keyboard"])) },
              read: { try parseProperty(run(readArguments($0)), device: $0) },
              write: { device, mappings in
                  let result = try parseProperty(run(writeArguments(device, mappings: mappings)), device: device)
                  guard result.mappings == mappings else { throw SessionCapsMappingLease.Refusal.unverifiedWrite }
              })
    }

    public static func runHIDUtil(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let output = Pipe(), error = Pipe()
        process.standardOutput = output
        process.standardError = error
        let handles = [output.fileHandleForReading, error.fileHandleForReading]
        defer { for handle in handles { try? handle.close() } }
        for handle in handles {
            guard fcntl(handle.fileDescriptor, F_SETFL, O_NONBLOCK) == 0 else { throw Refusal.commandFailed }
        }
        let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        try process.run()
        try? output.fileHandleForWriting.close()
        try? error.fileHandleForWriting.close()
        defer { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
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
                else if errno != EAGAIN && errno != EINTR { throw Refusal.commandFailed }
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
