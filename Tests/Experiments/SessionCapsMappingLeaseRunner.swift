import Darwin
import Foundation
import KeyPathCore

@main
struct SessionCapsMappingLeaseRunner {
    typealias Lease = SessionCapsMappingLease
    typealias Policy = SessionCapsMappingPolicy
    enum Failure: Error { case simulated }
    static let device = Policy.DeviceIdentity(registryEntryID: 42, vendorID: 0x303A, productID: 0x4002,
                                              serialNumber: "fixture", locationID: 123)
    static let owner = Policy.Owner(uid: getuid(), parentPID: 100, workerPID: 101, nonce: "nonce",
                                    generation: "one", bootSessionUUID: "A7B944DF-471A-4C22-B9F3-A4EE5522F775")
    static let digest = String(repeating: "a", count: 64)
    static let original = [Policy.Mapping(source: 0x7_0000_0004, destination: 0xC_0000_00E9)]
    final class Fake {
        var mappings = original
        var devices = [device]
        var failWrite = false
        var failRead = false
        var afterWrite: (() throws -> Void)?
        var writes = 0
        var backend: Lease.Backend {
            .init(enumerate: { self.devices }, read: { identity in
                if self.failRead { throw Failure.simulated }
                return .init(device: identity, mappings: self.mappings)
            }, write: { _, value in
                self.writes += 1
                if self.failWrite { throw Failure.simulated }
                self.mappings = value
                try self.afterWrite?()
            })
        }
    }

    static func check(_ value: @autoclosure () throws -> Bool) throws {
        let result = try value()
        precondition(result)
    }

    static func refused(_ body: () throws -> Void) {
        do { try body(); fatalError("expected refusal") } catch {}
    }

    static func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return url
    }

    static func scenario(_ body: (URL, Fake, Lease) throws -> Void) throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = Fake()
        try body(root, fake, Lease(directory: root, backend: fake.backend))
    }

    static func acquire(_ lease: Lease) throws -> Policy.Record {
        try lease.acquire(owner: owner, configSHA256: digest, device: device)
    }

    static func restore(_ lease: Lease) throws {
        try lease.restore(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID)
    }

    static func main() throws {
        try scenario { _, fake, lease in
            let record = try acquire(lease)
            try check(record.original == original && fake.mappings == record.applied)
            refused { _ = try acquire(lease) }
            try check(fake.writes == 1)
            try restore(lease)
            try check(fake.mappings == original && (lease.pendingRecord()) == nil)
        }
        try scenario { _, fake, lease in
            let record = try acquire(lease)
            fake.mappings.append(.init(source: 0x7_0000_0005, destination: 0x7_0000_0006))
            let changed = fake.mappings
            refused { try restore(lease) }
            try check(fake.mappings == changed && (lease.pendingRecord()) == record)
        }
        try scenario { root, fake, lease in
            fake.failWrite = true
            refused { _ = try acquire(lease) }
            try check(lease.pendingRecord() != nil)
            fake.failWrite = false
            try restore(Lease(directory: root, backend: fake.backend))
            try check(lease.pendingRecord() == nil)
        }
        try scenario { root, fake, lease in
            fake.afterWrite = { fake.failRead = true }
            refused { _ = try acquire(lease) }
            fake.failRead = false
            fake.afterWrite = nil
            try check(lease.pendingRecord() != nil)
            try restore(Lease(directory: root, backend: fake.backend))
            try check(fake.mappings == original)
        }
        try scenario { _, fake, lease in
            let record = try acquire(lease)
            let foreign = Policy.Owner(uid: owner.uid, parentPID: 100, workerPID: 102, nonce: "other",
                                       generation: "one", bootSessionUUID: owner.bootSessionUUID)
            refused { try lease.restore(expectedOwner: foreign, bootSessionUUID: owner.bootSessionUUID) }
            refused { try lease.restore(expectedOwner: owner, bootSessionUUID: UUID().uuidString) }
            fake.devices = [.init(registryEntryID: 43, vendorID: device.vendorID, productID: device.productID,
                                  serialNumber: device.serialNumber, locationID: device.locationID)]
            refused { try restore(lease) }
            try check(lease.pendingRecord() == record)
        }
        try scenario { root, _, lease in
            let target = root.appendingPathComponent("target")
            try Data("test".utf8).write(to: target)
            let journal = root.appendingPathComponent("caps-mapping-intent.json")
            try FileManager.default.createSymbolicLink(at: journal, withDestinationURL: target)
            refused { _ = try acquire(lease) }
            try check(Data(contentsOf: target) == Data("test".utf8))
            try FileManager.default.removeItem(at: journal)
            _ = try acquire(lease)
            chmod(journal.path, 0o644)
            refused { try restore(lease) }
            try check(FileManager.default.fileExists(atPath: journal.path))
        }
        try scenario { root, fake, lease in
            let other = Lease(directory: root, backend: fake.backend)
            fake.afterWrite = { refused { _ = try other.pendingRecord() } }
            _ = try acquire(lease)
            fake.afterWrite = nil
            chmod(root.path, 0o755)
            refused { _ = try lease.pendingRecord() }
        }
        try scenario { root, fake, lease in
            let record = try acquire(lease)
            fake.afterWrite = { fake.failRead = true }
            refused { try restore(lease) }
            fake.failRead = false
            fake.afterWrite = nil
            try check(lease.pendingRecord() == record)
            // Crash after restore write but before its verified readback: next
            // launch sees exact original and clears intent without writing.
            try restore(Lease(directory: root, backend: fake.backend))
            try check(lease.pendingRecord() == nil && fake.writes == 2)
        }
        try scenario { root, fake, lease in
            let record = try acquire(lease)
            let path = root.appendingPathComponent("caps-mapping-intent.json")
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
            var changedOwner = json["owner"] as! [String: Any]
            changedOwner["uid"] = owner.uid + 1
            json["owner"] = changedOwner
            try JSONSerialization.data(withJSONObject: json).write(to: path)
            let foreign = try lease.pendingRecord()!
            refused { try lease.restore(expectedOwner: foreign.owner, bootSessionUUID: owner.bootSessionUUID) }
            try check(fake.mappings == record.applied && fake.writes == 1)
        }
        try scenario { root, _, lease in
            let target = root.appendingPathComponent("lock-target")
            try Data().write(to: target)
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("caps-mapping.lock"), withDestinationURL: target)
            refused { _ = try lease.pendingRecord() }
        }
        try scenario { root, _, lease in
            let fifo = root.appendingPathComponent("caps-mapping-intent.json")
            try check(mkfifo(fifo.path, 0o600) == 0)
            let started = Date()
            refused { _ = try lease.pendingRecord() }
            try check(Date().timeIntervalSince(started) < 1)
        }
        try scenario { root, fake, lease in
            _ = try acquire(lease)
            let journal = root.appendingPathComponent("caps-mapping-intent.json")
            let replacement = root.appendingPathComponent("replacement.json")
            let bytes = try Data(contentsOf: journal)
            fake.afterWrite = {
                try! bytes.write(to: replacement)
                chmod(replacement.path, 0o600)
                try! FileManager.default.removeItem(at: journal)
                try! FileManager.default.moveItem(at: replacement, to: journal)
            }
            refused { try restore(lease) }
            try check(FileManager.default.fileExists(atPath: journal.path))
            try check(Data(contentsOf: journal) == bytes)
        }
        let header = "RegistryID  Key                   Value\n2a   UserKeyMapping   "
        let row = "{ HIDKeyboardModifierMappingDst = 30064771181; HIDKeyboardModifierMappingSrc = 30064771129; }"
        try check(SessionCapsHIDUtilTransport.parseProperty(header + "(\n)", device: device).mappings == [])
        try check(SessionCapsHIDUtilTransport.parseProperty(header + "(" + row + ")", device: device).mappings == [.init(source: Policy.caps, destination: Policy.f18)])
        for bad in ["", header + "(null, {})", header + "(" + row + ") trailing",
                    header + "(" + row + ")\n2a UserKeyMapping ()",
                    header + "({ HIDKeyboardModifierMappingSrc = 30064771129; HIDKeyboardModifierMappingSrc = 30064771129; })",
                    header + "({ Unknown = 1; HIDKeyboardModifierMappingSrc = 30064771129; })",
                    header.replacingOccurrences(of: "2a", with: "2b") + "()"]
        {
            refused { _ = try SessionCapsHIDUtilTransport.parseProperty(bad, device: device) }
        }
        let args = try SessionCapsHIDUtilTransport.readArguments(device)
        try check(args.count == 5 && args[0] == "property" && args[4] == "UserKeyMapping")
        let match = try JSONSerialization.jsonObject(with: Data(args[2].utf8)) as! [String: Any]
        try check(match["SerialNumber"] == nil && (match["IOPropertyMatch"] as? [String: String])?["SerialNumber"] == "fixture")
        let liveDevice = Policy.DeviceIdentity(registryEntryID: 4_294_968_825, vendorID: 51966, productID: 16400,
                                               serialNumber: nil, locationID: 261_095_424)
        // Exact output from the public-UID 502 owned guest qualification.
        let service = #"{"Product":"KeyPath Physical HID Fixture","VendorID":51966,"IOUserClass":"AppleUserHIDEventDriver","IOClass":"AppleUserHIDEventService","type":"service","PrimaryUsage":6,"PrimaryUsagePage":1,"IORegistryEntryID":4294968825,"Transport":"USB","LocationID":261095424,"ProductID":16400}"#
        let virtual = #"{"Product":"Virtual Keyboard","VendorID":1452,"Built-In":true,"type":"service","PrimaryUsage":6,"PrimaryUsagePage":1,"IORegistryEntryID":3530398491475969,"Transport":"AppleVirtualPlatformHIDBridge","LocationID":0,"ProductID":1}"#
        try check(SessionCapsHIDUtilTransport.parseServices(virtual + "\n" + service) == [liveDevice])
        let deviceRow = #"{"IOClass":"AppleUserHIDDevice","VendorID":51966,"Product":"KeyPath Physical HID Fixture","type":"device","PrimaryUsage":6,"LocationID":261095424,"IORegistryEntryID":4294968819,"ProductID":16400,"Transport":"USB","Manufacturer":"KeyPath Lab","PrimaryUsagePage":1,"IOUserClass":"AppleUserUSBHostHIDDevice"}"#
        let liveNull = "RegistryID  Key                   Value\n1000005f9   UserKeyMapping   (null)\n"
        try check(SessionCapsHIDUtilTransport.parseServices(service + "\n" + deviceRow + "\n") == [liveDevice])
        try check(SessionCapsHIDUtilTransport.parseProperty(liveNull, device: liveDevice).mappings == [])
        for malformed in ["{", "[]", service + "\n{}", service + "\n" + service,
                          service.replacingOccurrences(of: "4294968825", with: "4294968826") + "\n" + service,
                          service.replacingOccurrences(of: "51966", with: "true"),
                          service.replacingOccurrences(of: "51966", with: "51966.0"),
                          service.replacingOccurrences(of: "51966", with: "65536"),
                          service.replacingOccurrences(of: "261095424", with: "4294967296"),
                          service.replacingOccurrences(of: "261095424", with: "0"),
                          service.replacingOccurrences(of: "4294968825", with: "18446744073709551616"),
                          service.replacingOccurrences(of: "AppleUserHIDEventService", with: "AppleUserHIDDevice")]
        {
            refused { _ = try SessionCapsHIDUtilTransport.parseServices(malformed) }
        }
        let mouse = service.replacingOccurrences(of: "\"PrimaryUsage\":6", with: "\"PrimaryUsage\":2")
        try check(SessionCapsHIDUtilTransport.parseServices(mouse) == [])
        var commands: [[String]] = []
        let backend = SessionCapsHIDUtilTransport.backend { arguments in
            commands.append(arguments)
            if arguments[0] == "list" { return service + "\n" + deviceRow }
            if arguments.contains("--get") { return liveNull }
            return "RegistryID  Key                   Value\n1000005f9 UserKeyMapping (" + row + ")"
        }
        try check(backend.enumerate() == [liveDevice])
        try check(backend.read(liveDevice).mappings == [])
        try backend.write(liveDevice, [.init(source: Policy.caps, destination: Policy.f18)])
        try check(commands.count == 3 && commands[0] == ["list", "--ndjson", "--matching", "keyboard"])
        let selector = try JSONSerialization.jsonObject(with: Data(commands[1][2].utf8)) as! [String: Any]
        try check((selector["LocationID"] as? NSNumber)?.uint32Value == 261_095_424 && selector["IOPropertyMatch"] == nil)
        let falseWrite = SessionCapsHIDUtilTransport.backend { _ in liveNull }
        refused { try falseWrite.write(liveDevice, [.init(source: Policy.caps, destination: Policy.f18)]) }
        let overLimit = SessionCapsHIDUtilTransport.backend { _ in String(repeating: "x", count: 65537) }
        refused { _ = try overLimit.enumerate() }
        refused { _ = try overLimit.read(liveDevice) }
        let failed = SessionCapsHIDUtilTransport.backend { _ in throw Failure.simulated }
        refused { _ = try failed.enumerate() }
        refused { _ = try failed.read(liveDevice) }
        refused { try failed.write(liveDevice, []) }
        print("PASS: durable Caps lease fake transport scenarios")
    }
}
