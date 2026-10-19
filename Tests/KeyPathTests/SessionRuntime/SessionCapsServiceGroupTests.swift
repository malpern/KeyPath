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

    // Live report descriptors from the mini's cl80 (ioreg ReportDescriptor).
    static let sharedDescriptor = "05010902a10185020901a100050919012905150025019505750181029501750381010501093009311581257f95027508810609381581257f950175088106050c0a38021581257f950175088106c0c005010980a101850319012ab700150126b700950175108100c0050c0901a101850419012aa002150126a002950175108100c005010906a1018506050719e029e7150025019508750181020507190029ef1500250195f075018102050819012905950575019102950175039101c0"
    static let bootDescriptor = "05010906a101050719e029e7150025019508750181029501750881010507190029ff150026ff00950675088100050819012905950575019102950175039101c0"

    static func bytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map {
            let start = hex.index(hex.startIndex, offsetBy: $0)
            return UInt8(hex[start ..< hex.index(start, offsetBy: 2)], radix: 16)!
        }
    }

    func testDescriptorParsingFindsKeyboardInputOnly() {
        XCTAssertTrue(Transport.descriptorHasKeyboardInput(Self.bytes(Self.sharedDescriptor)), "NKRO collection, report 6")
        XCTAssertTrue(Transport.descriptorHasKeyboardInput(Self.bytes(Self.bootDescriptor)))
        // Mouse only: buttons and X/Y inputs.
        XCTAssertFalse(Transport.descriptorHasKeyboardInput(Self.bytes("05010902a1010901a100050919012903150025019503750181020501093009311581257f750895028106c0c0")))
        // Keyboard page in a feature report, LEDs as outputs: no keyboard input.
        XCTAssertFalse(Transport.descriptorHasKeyboardInput(Self.bytes("0507190029ff150026ff009501750bb102050819012905950575019102")))
        // Push/Pop restores the page that was current at Push.
        XCTAssertFalse(Transport.descriptorHasKeyboardInput(Self.bytes("0501a40507b48102")))
        XCTAssertTrue(Transport.descriptorHasKeyboardInput(Self.bytes("0507a40501b48102")))
        // Truncated input never claims anything.
        XCTAssertFalse(Transport.descriptorHasKeyboardInput(Self.bytes("05")))
        XCTAssertFalse(Transport.descriptorHasKeyboardInput(Self.bytes("fe")))
    }

    func testServiceGroupAddsKeyboardCapableInterfacesOfTheSameDevice() throws {
        let hid = FakeHID()
        let rows = try Transport.parseServiceRows(hid.listOutput(matching: nil))
        XCTAssertEqual(rows.map(\.registryEntryID).sorted(), [FakeHID.otherBoard, FakeHID.nkro, FakeHID.boot])
        let group = try Transport.serviceGroup(for: hid.cl80, rows: rows, emitsKeyboardUsages: { $0 == FakeHID.nkro })
        XCTAssertEqual(group.members, [FakeHID.boot, FakeHID.nkro])
        XCTAssertEqual(group.pairs, [[1, 6], [1, 2]])
        // An interface without keyboard usages, or unreadable, is not added.
        for answer: Bool? in [false, nil] {
            let alone = try Transport.serviceGroup(for: hid.cl80, rows: rows, emitsKeyboardUsages: { _ in answer })
            XCTAssertEqual(alone.members, [FakeHID.boot])
        }
        let gone = Policy.DeviceIdentity(registryEntryID: 1, vendorID: 21577, productID: 37148, serialNumber: nil, locationID: 34_673_408)
        XCTAssertThrowsError(try Transport.serviceGroup(for: gone, rows: rows, emitsKeyboardUsages: { _ in true }))
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

    func testLeaseMapsAndRestoresEveryInterface() throws {
        try fixture { lease, hid, owner in
            let record = try lease.acquire(owner: owner, configSHA256: String(repeating: "a", count: 64), device: hid.cl80)
            XCTAssertEqual(hid.state[FakeHID.boot], record.applied)
            XCTAssertEqual(hid.state[FakeHID.nkro], record.applied)
            XCTAssertEqual(hid.state[FakeHID.otherBoard], [])
            try lease.restore(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID)
            XCTAssertEqual(hid.state[FakeHID.boot], [])
            XCTAssertEqual(hid.state[FakeHID.nkro], [])
            XCTAssertNil(try lease.pendingRecord())
        }
    }

    func testPartialWriteIsRestoredOnEveryInterface() throws {
        try fixture { lease, hid, owner in
            hid.failSetOnPair = [1, 2]
            XCTAssertThrowsError(try lease.acquire(owner: owner, configSHA256: String(repeating: "a", count: 64), device: hid.cl80))
            XCTAssertNotEqual(hid.state[FakeHID.boot], [], "the boot interface took the write")
            XCTAssertEqual(hid.state[FakeHID.nkro], [])
            XCTAssertNotNil(try lease.pendingRecord())
            // Disagreeing interfaces are never reported as one mapping.
            XCTAssertThrowsError(try Transport.backend(run: hid.run, emitsKeyboardUsages: hid.emits).read(hid.cl80)) { error in
                XCTAssertEqual(error as? Policy.Refusal, .foreignMapping)
            }
            hid.failSetOnPair = nil
            try lease.restore(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID)
            XCTAssertEqual(hid.state[FakeHID.boot], [])
            XCTAssertEqual(hid.state[FakeHID.nkro], [])
            XCTAssertNil(try lease.pendingRecord())
        }
    }

    func testForeignMappingOnAnyInterfaceRefusesAndIsLeftAlone() throws {
        let raycast = [Policy.Mapping(source: Policy.caps, destination: 0x7_0000_006F)]
        try fixture { lease, hid, owner in
            hid.state[FakeHID.nkro] = raycast
            XCTAssertThrowsError(try lease.acquire(owner: owner, configSHA256: String(repeating: "a", count: 64), device: hid.cl80))
            XCTAssertEqual(hid.state[FakeHID.nkro], raycast)
            XCTAssertEqual(hid.state[FakeHID.boot], [])
            XCTAssertNil(try lease.pendingRecord())
        }
        try fixture { lease, hid, owner in
            _ = try lease.acquire(owner: owner, configSHA256: String(repeating: "a", count: 64), device: hid.cl80)
            hid.state[FakeHID.nkro] = raycast
            XCTAssertThrowsError(try lease.restore(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID))
            XCTAssertEqual(hid.state[FakeHID.nkro], raycast)
            XCTAssertNotNil(try lease.pendingRecord())
        }
    }

    func testOwnCapsRowOnACompanionInterfaceIsNotAnOccupiedKey() throws {
        let hid = FakeHID()
        hid.state[FakeHID.boot] = [.init(source: Policy.caps, destination: Policy.f18)]
        hid.state[FakeHID.nkro] = [.init(source: Policy.caps, destination: Policy.f18)]
        let taken = try SessionCapsRuntimeSupport.occupiedIntermediates(own: hid.cl80, run: hid.run, shortcutKeyCodes: { [] })
        XCTAssertFalse(taken.contains(109), "F18 is our own lease on both cl80 interfaces")
        hid.state[FakeHID.otherBoard] = [.init(source: Policy.caps, destination: Policy.f18)]
        XCTAssertTrue(try SessionCapsRuntimeSupport.occupiedIntermediates(own: hid.cl80, run: hid.run, shortcutKeyCodes: { [] }).contains(109))
    }

    private func fixture(_ body: (SessionCapsMappingLease, FakeHID, Policy.Owner) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let hid = FakeHID()
        let owner = Policy.Owner(uid: getuid(), parentPID: 100, workerPID: 101, nonce: "nonce",
                                 generation: "one", bootSessionUUID: UUID().uuidString)
        let backend = Transport.backend(run: hid.run, emitsKeyboardUsages: hid.emits)
        try body(SessionCapsMappingLease(directory: root, backend: backend), hid, owner)
    }
}

/// hidutil as the transport drives it, over the cl80's two event services
/// (boot keyboard 1/6, shared NKRO 1/2) and one unrelated keyboard.
final class FakeHID {
    static let boot: UInt64 = 4_300_977_972
    static let nkro: UInt64 = 4_300_977_963
    static let otherBoard: UInt64 = 4_294_972_747

    struct Service { let id: UInt64; let vendor: Int; let product: Int; let location: Int; let page: Int; let usage: Int; let name: String }
    let services = [
        Service(id: FakeHID.nkro, vendor: 21577, product: 37148, location: 34_673_408, page: 1, usage: 2, name: "cl80"),
        Service(id: FakeHID.boot, vendor: 21577, product: 37148, location: 34_673_408, page: 1, usage: 6, name: "cl80"),
        Service(id: FakeHID.otherBoard, vendor: 13652, product: 62727, location: 34_677_248, page: 1, usage: 6, name: "X2A")
    ]
    var state: [UInt64: [SessionCapsMappingPolicy.Mapping]] = [FakeHID.nkro: [], FakeHID.boot: [], FakeHID.otherBoard: []]
    var failSetOnPair: [Int]?
    let cl80 = SessionCapsMappingPolicy.DeviceIdentity(registryEntryID: FakeHID.boot, vendorID: 21577, productID: 37148,
                                                       serialNumber: nil, locationID: 34_673_408)

    func emits(_ id: UInt64) -> Bool? {
        id == FakeHID.nkro || id == FakeHID.boot
    }

    func listOutput(matching: [String: Any]?) -> String {
        services.filter { matches($0, matching) }.map {
            #"{"Product":"\#($0.name)","VendorID":\#($0.vendor),"IOClass":"AppleUserHIDEventService","type":"service","PrimaryUsage":\#($0.usage),"PrimaryUsagePage":\#($0.page),"IORegistryEntryID":\#($0.id),"Transport":"USB","LocationID":\#($0.location),"ProductID":\#($0.product)}"#
        }.joined(separator: "\n") + "\n"
    }

    private func matches(_ service: Service, _ match: [String: Any]?) -> Bool {
        guard let match else { return true }
        let fields: [String: Int] = ["VendorID": service.vendor, "ProductID": service.product, "LocationID": service.location,
                                     "PrimaryUsagePage": service.page, "PrimaryUsage": service.usage]
        return match.allSatisfy { key, value in
            key == "IOPropertyMatch" ? false : fields[key] == (value as? NSNumber)?.intValue
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
        if arguments == ["property", "--get", "UserKeyMapping"] { return propertyOutput(services.map(\.id)) }
        let isList = arguments.first == "list"
        let match = try JSONSerialization.jsonObject(with: Data(arguments[isList ? 3 : 2].utf8)) as! [String: Any]
        if isList { return listOutput(matching: match) }
        let ids = services.filter { matches($0, match) }.map(\.id)
        if arguments[3] == "--set" {
            let pair = [(match["PrimaryUsagePage"] as! NSNumber).intValue, (match["PrimaryUsage"] as! NSNumber).intValue]
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
