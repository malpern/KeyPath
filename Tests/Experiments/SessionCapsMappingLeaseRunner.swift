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
        for bad in ["", header + "(null)", header + "(" + row + ") trailing",
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
        print("PASS: durable Caps lease fake transport scenarios")
    }
}
