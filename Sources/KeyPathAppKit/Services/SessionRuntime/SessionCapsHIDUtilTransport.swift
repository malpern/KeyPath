import Foundation
import KeyPathCore

/// Only the property output grammar witnessed in the owned physical-fixture
/// guest is accepted. Enumeration of IOHID *event services* is not yet qualified;
/// callers must refuse acquisition rather than substitute an IOHIDDevice ID.
public enum SessionCapsHIDUtilTransport {
    public enum Refusal: Error { case unsupportedOutput }
    public typealias Policy = SessionCapsMappingPolicy

    public static func selector(_ device: Policy.DeviceIdentity) throws -> String {
        var match: [String: Any] = ["VendorID": device.vendorID, "ProductID": device.productID,
                                    "PrimaryUsagePage": 1, "PrimaryUsage": 6]
        if let location = device.locationID { match["LocationID"] = location }
        // SerialNumber is not a supported top-level matching key in hidutil help.
        if let serial = device.serialNumber { match["IOPropertyMatch"] = ["SerialNumber": serial] }
        guard device.locationID != nil || device.serialNumber != nil else { throw Policy.Refusal.invalidDevice }
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
}
