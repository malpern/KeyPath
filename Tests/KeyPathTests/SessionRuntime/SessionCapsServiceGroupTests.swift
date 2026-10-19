import Darwin
import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// A keyboard can deliver its keys on more than one HID interface. Witnessed
/// on 2026-10-19: a Vial/QMK "cl80" in NKRO mode sends Caps on its shared,
/// mouse-primary interface, which a boot-interface-only lease never maps.
final class SessionCapsServiceGroupTests: XCTestCase {
    typealias Policy = SessionCapsMappingPolicy
    typealias Transport = SessionCapsHIDUtilTransport
    let digest = String(repeating: "a", count: 64)
    let raycast = [Policy.Mapping(source: Policy.caps, destination: 0x7_0000_006F)]
    /// A non-Caps mapping another tool already applied (Right Option to Right Command).
    let existing = [Policy.Mapping(source: 0x7_0000_00E6, destination: 0x7_0000_00E7)]

    // Live report descriptors from the mini's cl80 (ioreg ReportDescriptor).
    static let sharedDescriptor = "05010902a10185020901a100050919012905150025019505750181029501750381010501093009311581257f95027508810609381581257f950175088106050c0a38021581257f950175088106c0c005010980a101850319012ab700150126b700950175108100c0050c0901a101850419012aa002150126a002950175108100c005010906a1018506050719e029e7150025019508750181020507190029ef1500250195f075018102050819012905950575019102950175039101c0"
    static let bootDescriptor = "05010906a101050719e029e7150025019508750181029501750881010507190029ff150026ff00950675088100050819012905950575019102950175039101c0"

    static func bytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map {
            let start = hex.index(hex.startIndex, offsetBy: $0)
            return UInt8(hex[start ..< hex.index(start, offsetBy: 2)], radix: 16)!
        }
    }

    func testDescriptorParsingFindsKeyboardDataInputOnly() {
        XCTAssertTrue(Transport.descriptorHasKeyboardInput(Self.bytes(Self.sharedDescriptor)), "NKRO collection, report 6")
        XCTAssertTrue(Transport.descriptorHasKeyboardInput(Self.bytes(Self.bootDescriptor)))
        // Mouse only: buttons and X/Y inputs.
        XCTAssertFalse(Transport.descriptorHasKeyboardInput(Self.bytes("05010902a1010901a100050919012903150025019503750181020501093009311581257f750895028106c0c0")))
        // Keyboard page in a feature report, LEDs as outputs: no keyboard input.
        XCTAssertFalse(Transport.descriptorHasKeyboardInput(Self.bytes("0507190029ff150026ff009501750bb102050819012905950575019102")))
        // Constant padding on the keyboard page is not input.
        XCTAssertFalse(Transport.descriptorHasKeyboardInput(Self.bytes("050795017508810105019502750881028103")))
        // Push/Pop restores the page that was current at Push.
        XCTAssertFalse(Transport.descriptorHasKeyboardInput(Self.bytes("0501a40507b48102")))
        XCTAssertTrue(Transport.descriptorHasKeyboardInput(Self.bytes("0507a40501b48102")))
        // 32-bit extended usages name the keyboard page without a Usage Page item.
        XCTAssertTrue(Transport.descriptorHasKeyboardInput(Self.bytes("0501" + "1b00000700" + "2be7000700" + "8102")))
        XCTAssertFalse(Transport.descriptorHasKeyboardInput(Self.bytes("0501" + "0b39000700" + "c0" + "8102")), "locals end at a main item")
        // A long item (0xFE, data size, tag, data) is skipped whole.
        XCTAssertTrue(Transport.descriptorHasKeyboardInput(Self.bytes("fe0201aabb" + "0507" + "8102")))
        XCTAssertFalse(Transport.descriptorHasKeyboardInput(Self.bytes("fe0201aabb" + "0501" + "8102")))
        // Truncated input never claims anything.
        XCTAssertFalse(Transport.descriptorHasKeyboardInput(Self.bytes("05")))
        XCTAssertFalse(Transport.descriptorHasKeyboardInput(Self.bytes("fe")))
    }

    func testServiceGroupAddsKeyboardCapableInterfacesOfTheSameDevice() throws {
        let hid = FakeHID()
        let rows = try Transport.parseServiceRows(hid.listOutput(matching: nil))
        XCTAssertEqual(Set(rows.map(\.registryEntryID)), [FakeHID.nkro, FakeHID.boot, FakeHID.consumer, FakeHID.otherBoard])
        let group = try Transport.serviceGroup(for: hid.cl80, rows: rows, emitsKeyboardUsages: hid.emits)
        XCTAssertEqual(group.members, [FakeHID.boot, FakeHID.nkro])
        XCTAssertEqual(group.pairs, [[1, 6], [1, 2]])
        XCTAssertEqual(group.unreadable, [])
        // An interface without keyboard usages is not added; unreadable ones are reported.
        let alone = try Transport.serviceGroup(for: hid.cl80, rows: rows, emitsKeyboardUsages: { _ in false })
        XCTAssertEqual(alone.members, [FakeHID.boot])
        let unknown = try Transport.serviceGroup(for: hid.cl80, rows: rows, emitsKeyboardUsages: { _ in nil })
        XCTAssertEqual(unknown.members, [FakeHID.boot])
        XCTAssertEqual(Set(unknown.unreadable), [FakeHID.nkro, FakeHID.consumer])
        let gone = Policy.DeviceIdentity(registryEntryID: 1, vendorID: 21577, productID: 37148, serialNumber: nil, locationID: 34_673_408)
        XCTAssertThrowsError(try Transport.serviceGroup(for: gone, rows: rows, emitsKeyboardUsages: { _ in true }))
    }

    func testInterfaceWithoutTheSerialIsStillCovered() throws {
        let hid = FakeHID(bootSerial: "S1")
        try fixture(hid) { lease, hid, owner in
            let record = try lease.acquire(owner: owner, configSHA256: digest, device: hid.cl80)
            XCTAssertEqual(record.companions.map(\.registryEntryID), [FakeHID.nkro])
            XCTAssertEqual(hid.state[FakeHID.nkro], record.applied)
            XCTAssertTrue(hid.selectors.contains { $0.contains("S1") && $0.contains(#""PrimaryUsage":6"#) },
                          "the chosen service is still matched by its serial")
            XCTAssertTrue(hid.selectors.contains { !$0.contains("S1") && $0.contains(#""PrimaryUsage":2"#) })
        }
    }

    func testUnreadableInterfaceRefusesRatherThanLeaveCapsNative() throws {
        let hid = FakeHID()
        hid.unreadable = [FakeHID.nkro]
        try fixture(hid) { lease, hid, owner in
            XCTAssertThrowsError(try lease.acquire(owner: owner, configSHA256: digest, device: hid.cl80))
            XCTAssertEqual(hid.state[FakeHID.boot], [])
            XCTAssertEqual(hid.state[FakeHID.nkro], [])
            XCTAssertNil(try lease.pendingRecord())
        }
    }

    func testOnePairIsWrittenWholeSoItsTargetsMustAgree() throws {
        let hid = FakeHID()
        let twin = FakeHID.Service(id: 4_300_977_990, vendor: 21577, product: 37148, location: 34_673_408,
                                   page: 1, usage: 6, name: "cl80", serial: nil)
        hid.extra = [twin]
        hid.state[twin.id] = []
        let rows = try Transport.deviceRows(hid.cl80, rows: Transport.parseServiceRows(hid.listOutput(matching: nil)))
        let mapped = [Policy.Mapping(source: Policy.caps, destination: Policy.f18)]
        // Different targets for two services of the same pair: refused before writing.
        XCTAssertThrowsError(try Transport.writeTargets(hid.cl80, [FakeHID.boot: mapped, twin.id: []], rows: rows, run: hid.run))
        // A service the pair's selector reaches but that has no target: refused too.
        XCTAssertThrowsError(try Transport.writeTargets(hid.cl80, [FakeHID.boot: mapped], rows: rows, run: hid.run))
        XCTAssertEqual(hid.state[FakeHID.boot], [])
        XCTAssertEqual(hid.state[twin.id], [])
        try Transport.writeTargets(hid.cl80, [FakeHID.boot: mapped, twin.id: mapped], rows: rows, run: hid.run)
        XCTAssertEqual(hid.state[twin.id], mapped)
    }

    func testConflictCheckReadsOnlyCoveredInterfaces() throws {
        let hid = FakeHID()
        hid.state[FakeHID.nkro] = raycast
        hid.failGetOnPair = [12, 1] // the board's consumer interface is unreadable
        let conflict = try SessionCapsRuntimeSupport.capsConflict(on: hid.cl80, backend: hid.backend,
                                                                  raycast: .init(enabled: true, keyCode: 57))
        XCTAssertEqual(conflict, .raycastHyperKey)
    }

    func testBlankSerialCountsAsNone() throws {
        let row = #"{"type":"service","SerialNumber":"  ","IORegistryEntryID":5,"VendorID":1,"ProductID":2,"LocationID":3,"PrimaryUsagePage":1,"PrimaryUsage":2}"#
        XCTAssertNil(try Transport.parseServiceRows(row).first?.serialNumber)
    }

    func testTwoKeyboardInterfacesAtOneLocationAreOneKeyboard() throws {
        let first = #"{"Product":"cl80","VendorID":21577,"IOClass":"AppleUserHIDEventService","type":"service","PrimaryUsage":6,"PrimaryUsagePage":1,"IORegistryEntryID":4300977972,"Transport":"USB","LocationID":34673408,"ProductID":37148}"#
        let second = first.replacingOccurrences(of: "4300977972", with: "4300977960")
        let list = try Transport.parseKeyboardList(first + "\n" + second)
        XCTAssertEqual(list.keyboards.map(\.name), ["cl80"])
        XCTAssertEqual(list.keyboards.map(\.device.registryEntryID), [4_300_977_960], "lowest registry ID stands for the board")
        XCTAssertEqual(list.withheld, 0)
        // A duplicated registry ID is malformed, never a board: withheld.
        XCTAssertEqual(try Transport.parseInventory(first + "\n" + first), .init(devices: [], withheld: 1))
    }

    func testLeaseMapsAndRestoresEveryInterfaceToItsOwnOriginal() throws {
        try fixture(FakeHID()) { lease, hid, owner in
            hid.state[FakeHID.boot] = existing
            let record = try lease.acquire(owner: owner, configSHA256: digest, device: hid.cl80)
            XCTAssertEqual(record.version, 3)
            XCTAssertEqual(hid.state[FakeHID.boot], existing + [.init(source: Policy.caps, destination: Policy.f18)])
            XCTAssertEqual(hid.state[FakeHID.nkro], [.init(source: Policy.caps, destination: Policy.f18)])
            XCTAssertEqual(hid.state[FakeHID.consumer], [], "not a keyboard interface")
            XCTAssertEqual(hid.state[FakeHID.otherBoard], [])
            try lease.restore(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID)
            XCTAssertEqual(hid.state[FakeHID.boot], existing)
            XCTAssertEqual(hid.state[FakeHID.nkro], [])
            XCTAssertNil(try lease.pendingRecord())
        }
    }

    func testPartialWriteIsRestoredOnEveryInterface() throws {
        try fixture(FakeHID()) { lease, hid, owner in
            hid.failSetOnPair = [1, 2]
            XCTAssertThrowsError(try lease.acquire(owner: owner, configSHA256: digest, device: hid.cl80))
            XCTAssertNotEqual(hid.state[FakeHID.boot], [], "the boot interface took the write")
            XCTAssertEqual(hid.state[FakeHID.nkro], [])
            XCTAssertNotNil(try lease.pendingRecord())
            hid.failSetOnPair = nil
            try lease.restore(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID)
            XCTAssertEqual(hid.state[FakeHID.boot], [])
            XCTAssertEqual(hid.state[FakeHID.nkro], [])
            XCTAssertNil(try lease.pendingRecord())
        }
    }

    func testCoveredSetNeverShrinksOnRestore() throws {
        try fixture(FakeHID()) { lease, hid, owner in
            _ = try lease.acquire(owner: owner, configSHA256: digest, device: hid.cl80)
            // The NKRO interface still exists but is not listed: refuse, keep intent.
            hid.hidden = [FakeHID.nkro]
            XCTAssertThrowsError(try lease.restore(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID))
            XCTAssertNotNil(try lease.pendingRecord())
            XCTAssertNotEqual(hid.state[FakeHID.boot], [])
            // Once it is really gone, its mapping went with it; the rest restores.
            hid.gone = [FakeHID.nkro]
            try lease.restore(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID)
            XCTAssertEqual(hid.state[FakeHID.boot], [])
            XCTAssertNil(try lease.pendingRecord())
        }
    }

    func testCapsOnAnyInterfaceIsAlreadyMappedAndNamed() throws {
        try fixture(FakeHID()) { lease, hid, owner in
            hid.state[FakeHID.nkro] = raycast
            XCTAssertThrowsError(try lease.acquire(owner: owner, configSHA256: digest, device: hid.cl80)) { error in
                XCTAssertEqual(error as? Policy.Refusal, .capsAlreadyMapped)
            }
            XCTAssertEqual(hid.state[FakeHID.nkro], raycast)
            XCTAssertEqual(hid.state[FakeHID.boot], [])
            XCTAssertNil(try lease.pendingRecord())
            let conflict = try SessionCapsRuntimeSupport.capsConflict(on: hid.cl80, backend: hid.backend,
                                                                      raycast: .init(enabled: true, keyCode: 57))
            XCTAssertEqual(conflict, .raycastHyperKey)
        }
        try fixture(FakeHID()) { lease, hid, owner in
            _ = try lease.acquire(owner: owner, configSHA256: digest, device: hid.cl80)
            hid.state[FakeHID.nkro] = raycast
            XCTAssertThrowsError(try lease.restore(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID)) { error in
                XCTAssertEqual(error as? Policy.Refusal, .foreignMapping)
            }
            XCTAssertEqual(hid.state[FakeHID.nkro], raycast)
            XCTAssertNotNil(try lease.pendingRecord())
        }
    }

    func testOnlyOurOwnCoveredInterfacesAreExemptFromTheFreeKeyChoice() throws {
        let hid = FakeHID()
        hid.state[FakeHID.boot] = [.init(source: Policy.caps, destination: Policy.f18)]
        hid.state[FakeHID.nkro] = [.init(source: Policy.caps, destination: Policy.f18)]
        func taken() throws -> Set<UInt32> {
            try SessionCapsRuntimeSupport.occupiedIntermediates(own: hid.cl80, run: hid.run, shortcutKeyCodes: { [] },
                                                                emitsKeyboardUsages: hid.emits)
        }
        XCTAssertFalse(try taken().contains(109), "F18 is our own lease on both cl80 keyboard interfaces")
        // A Caps row on the board's consumer interface is not ours: F19 is taken.
        hid.state[FakeHID.consumer] = [.init(source: Policy.caps, destination: Policy.packed(110))]
        XCTAssertTrue(try taken().contains(110))
        hid.state[FakeHID.otherBoard] = [.init(source: Policy.caps, destination: Policy.f18)]
        XCTAssertTrue(try taken().contains(109))
    }

    func testRecordVersionThreeListsCompanionsAndVersionTwoStaysCompatible() throws {
        let device = FakeHID().cl80
        let owner = Policy.Owner(uid: 501, parentPID: 100, workerPID: 101, nonce: "n", generation: "g", bootSessionUUID: UUID().uuidString)
        let plain = try Policy.acquire(original: [], device: device, devices: [device], owner: owner, effectiveConfigSHA256: digest)
        XCTAssertEqual(plain.version, 2)
        XCTAssertFalse(try String(decoding: JSONEncoder().encode(plain), as: UTF8.self).contains("companions"))
        let grouped = try Policy.acquire(original: existing, device: device, devices: [device], owner: owner,
                                         effectiveConfigSHA256: digest, companions: [FakeHID.nkro: []])
        XCTAssertEqual(grouped.version, 3)
        let decoded = try JSONDecoder().decode(Policy.Record.self, from: JSONEncoder().encode(grouped))
        XCTAssertEqual(decoded, grouped)
        XCTAssertEqual(try Policy.restoreService(record: grouped, registryEntryID: FakeHID.nkro,
                                                 current: grouped.applied(over: []), bootSessionUUID: owner.bootSessionUUID), [])
        XCTAssertThrowsError(try Policy.restoreService(record: grouped, registryEntryID: FakeHID.nkro,
                                                       current: raycast, bootSessionUUID: owner.bootSessionUUID))
        XCTAssertThrowsError(try Policy.restoreService(record: grouped, registryEntryID: 7, current: [], bootSessionUUID: owner.bootSessionUUID))
        // The chosen service can never also be its own companion.
        XCTAssertThrowsError(try Policy.acquire(original: [], device: device, devices: [device], owner: owner,
                                                effectiveConfigSHA256: digest, companions: [device.registryEntryID: []]))
    }

    private func fixture(_ hid: FakeHID, _ body: (SessionCapsMappingLease, FakeHID, Policy.Owner) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = Policy.Owner(uid: getuid(), parentPID: 100, workerPID: 101, nonce: "nonce",
                                 generation: "one", bootSessionUUID: UUID().uuidString)
        try body(SessionCapsMappingLease(directory: root, backend: hid.backend), hid, owner)
    }
}

/// hidutil as the transport drives it, over the cl80's event services (boot
/// keyboard 1/6, shared NKRO 1/2, consumer 12/1) and one unrelated keyboard.
final class FakeHID {
    static let boot: UInt64 = 4_300_977_972
    static let nkro: UInt64 = 4_300_977_963
    static let consumer: UInt64 = 4_300_977_965
    static let otherBoard: UInt64 = 4_294_972_747

    struct Service { let id: UInt64; let vendor: Int; let product: Int; let location: Int; let page: Int; let usage: Int; let name: String; let serial: String? }
    let services: [Service]
    var state: [UInt64: [SessionCapsMappingPolicy.Mapping]] = [FakeHID.nkro: [], FakeHID.boot: [], FakeHID.consumer: [], FakeHID.otherBoard: []]
    var failSetOnPair: [Int]?
    var failGetOnPair: [Int]?
    var unreadable: Set<UInt64> = []
    var extra: [Service] = []
    var hidden: Set<UInt64> = []
    var gone: Set<UInt64> = []
    var selectors: [String] = []
    let cl80: SessionCapsMappingPolicy.DeviceIdentity

    init(bootSerial: String? = nil) {
        services = [
            Service(id: FakeHID.nkro, vendor: 21577, product: 37148, location: 34_673_408, page: 1, usage: 2, name: "cl80", serial: nil),
            Service(id: FakeHID.boot, vendor: 21577, product: 37148, location: 34_673_408, page: 1, usage: 6, name: "cl80", serial: bootSerial),
            Service(id: FakeHID.consumer, vendor: 21577, product: 37148, location: 34_673_408, page: 12, usage: 1, name: "cl80", serial: nil),
            Service(id: FakeHID.otherBoard, vendor: 13652, product: 62727, location: 34_677_248, page: 1, usage: 6, name: "X2A", serial: nil)
        ]
        cl80 = .init(registryEntryID: FakeHID.boot, vendorID: 21577, productID: 37148, serialNumber: bootSerial, locationID: 34_673_408)
    }

    func emits(_ id: UInt64) -> Bool? {
        unreadable.contains(id) ? nil : id == FakeHID.nkro || id == FakeHID.boot || id == FakeHID.otherBoard
    }

    var backend: SessionCapsMappingLease.Backend {
        SessionCapsHIDUtilTransport.backend(emitsKeyboardUsages: emits,
                                            registryEntryExists: { !self.gone.contains($0) }, run: run)
    }

    private var live: [Service] {
        (services + extra).filter { !hidden.contains($0.id) && !gone.contains($0.id) }
    }

    func listOutput(matching: [String: Any]?) -> String {
        live.filter { matches($0, matching) }.map { service in
            let serial = service.serial.map { #""SerialNumber":"\#($0)","# } ?? ""
            return #"{\#(serial)"Product":"\#(service.name)","VendorID":\#(service.vendor),"IOClass":"AppleUserHIDEventService","type":"service","PrimaryUsage":\#(service.usage),"PrimaryUsagePage":\#(service.page),"IORegistryEntryID":\#(service.id),"Transport":"USB","LocationID":\#(service.location),"ProductID":\#(service.product)}"#
        }.joined(separator: "\n") + "\n"
    }

    private func matches(_ service: Service, _ match: [String: Any]?) -> Bool {
        guard let match else { return true }
        let fields: [String: Int] = ["VendorID": service.vendor, "ProductID": service.product, "LocationID": service.location,
                                     "PrimaryUsagePage": service.page, "PrimaryUsage": service.usage]
        return match.allSatisfy { key, value in
            if key == "IOPropertyMatch" { return (value as? [String: String])?["SerialNumber"] == service.serial }
            return fields[key] == (value as? NSNumber)?.intValue
        }
    }

    private func propertyOutput(_ ids: [UInt64]) -> String {
        var text = "RegistryID  Key                   Value\n"
        for id in ids {
            let rows = state[id]!.map { "    {\n        HIDKeyboardModifierMappingDst = \($0.destination);\n        HIDKeyboardModifierMappingSrc = \($0.source);\n    }" }
            text += String(id, radix: 16) + "   UserKeyMapping   (" + (rows.isEmpty ? "\n)" : "\n" + rows.joined(separator: ",\n") + "\n)") + "\n"
        }
        return text
    }

    func run(_ arguments: [String]) throws -> String {
        if arguments == ["list", "--ndjson", "--matching", "keyboard"] {
            return listOutput(matching: ["PrimaryUsagePage": 1, "PrimaryUsage": 6])
        }
        if arguments == ["property", "--get", "UserKeyMapping"] { return propertyOutput(live.map(\.id)) }
        let isList = arguments.first == "list"
        let match = try JSONSerialization.jsonObject(with: Data(arguments[isList ? 3 : 2].utf8)) as! [String: Any]
        if isList { return listOutput(matching: match) }
        selectors.append(arguments[2])
        let ids = live.filter { matches($0, match) }.map(\.id)
        let pair = [(match["PrimaryUsagePage"] as? NSNumber)?.intValue ?? -1, (match["PrimaryUsage"] as? NSNumber)?.intValue ?? -1]
        if arguments[3] == "--get", pair == failGetOnPair { throw SessionCapsHIDUtilTransport.Refusal.commandFailed }
        if arguments[3] == "--set" {
            if pair == failSetOnPair { throw SessionCapsHIDUtilTransport.Refusal.commandFailed }
            let body = try JSONSerialization.jsonObject(with: Data(arguments[4].utf8)) as! [String: Any]
            let rows = try JSONSerialization.data(withJSONObject: body["UserKeyMapping"]!)
            let mappings = try JSONDecoder().decode([SessionCapsMappingPolicy.Mapping].self, from: rows)
            for id in ids {
                state[id] = mappings
            }
        }
        return propertyOutput(ids)
    }
}
