import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class SessionCapsSelectionTests: XCTestCase {
    func testAutomaticSelectionRejectsAmbiguousKeyboard() {
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.automaticSelection(devices: [], boot: UUID().uuidString))
    }

    func testAutomaticSelectionReservesInternalKeyForOneKeyboard() throws {
        let selection = try SessionCapsRuntimeSupport.automaticSelection(devices: [device], boot: boot)
        XCTAssertEqual(try selection.approvedDevice(currentBoot: boot), device)
        XCTAssertTrue(selection.reservesF18)
    }

    func testAutomaticSelectionRefusesMultipleKeyboards() {
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.automaticSelection(devices: [device, device], boot: boot))
    }

    func testAirBuiltInServiceCanBeSelectedAndRoundTripped() throws {
        let fixture = #"{"Product":"Apple Internal Keyboard / Trackpad","VendorID":0,"Built-In":true,"IOClass":"AppleHIDKeyboardEventDriverV2","type":"service","PrimaryUsage":6,"PrimaryUsagePage":1,"IORegistryEntryID":4294970189,"Transport":"FIFO","LocationID":231,"ProductID":0}"#
        let devices = try SessionCapsHIDUtilTransport.parseServices(fixture)
        let selected = try SessionCapsRuntimeSupport.automaticSelection(devices: devices, boot: boot)
        XCTAssertEqual(selected.device.appleBuiltIn, true)
        XCTAssertEqual(try SessionCapsSelection.decode(JSONEncoder().encode(selected), currentBoot: boot), selected)
        let snapshot = try SessionCapsHIDUtilTransport.parseProperty("RegistryID Key Value\n100000b4d UserKeyMapping (\n)", device: selected.device)
        XCTAssertTrue(snapshot.mappings.isEmpty)
        for bad in [fixture.replacingOccurrences(of: "FIFO", with: "USB"), fixture.replacingOccurrences(of: "true", with: "false")] {
            XCTAssertEqual(try SessionCapsHIDUtilTransport.parseInventory(bad), .init(devices: [], withheld: 1))
        }
        XCTAssertThrowsError(try SessionCapsHIDUtilTransport.selector(.init(registryEntryID: 42, vendorID: 0, productID: 0, serialNumber: nil, locationID: 231)))
    }

    private let boot = UUID().uuidString
    private let device = SessionCapsMappingPolicy.DeviceIdentity(registryEntryID: 42, vendorID: 1234,
                                                                 productID: 5678, serialNumber: nil, locationID: 123)

    func testConsentRequiresCurrentBootAndF18Reservation() throws {
        let selected = SessionCapsSelection(device: device, bootSessionUUID: boot, reservesF18: true)
        XCTAssertEqual(try selected.approvedDevice(currentBoot: boot.lowercased()), device)
        XCTAssertThrowsError(try selected.approvedDevice(currentBoot: UUID().uuidString))
        XCTAssertThrowsError(try selected.approvedDevice(currentBoot: "invalid"))
        XCTAssertThrowsError(try SessionCapsSelection(device: device, bootSessionUUID: boot, reservesF18: false).approvedDevice(currentBoot: boot))
    }

    func testSelectionNeverRebindsChangedOrAmbiguousRegistryInstance() throws {
        let selected = SessionCapsSelection(device: device, bootSessionUUID: boot, reservesF18: true)
        let replacement = SessionCapsMappingPolicy.DeviceIdentity(registryEntryID: 43, vendorID: device.vendorID,
                                                                  productID: device.productID, serialNumber: nil, locationID: device.locationID)
        XCTAssertNoThrow(try selected.verifyConnected(devices: [device], currentBoot: boot))
        for devices in [[], [replacement], [device, replacement], [device, device]] {
            XCTAssertThrowsError(try selected.verifyConnected(devices: devices, currentBoot: boot))
        }
    }

    func testChosenKeyboardIsAcceptedBesideOtherKeyboards() throws {
        let selected = SessionCapsSelection(device: device, bootSessionUUID: boot, reservesF18: true)
        let other = SessionCapsMappingPolicy.DeviceIdentity(registryEntryID: 99, vendorID: 4321,
                                                            productID: 8765, serialNumber: nil, locationID: 456)
        XCTAssertNoThrow(try selected.verifyConnected(devices: [other, device], currentBoot: boot))
        XCTAssertThrowsError(try selected.verifyConnected(devices: [other], currentBoot: boot))
        // Automatic selection still never picks one of several keyboards.
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.automaticSelection(devices: [other, device], boot: boot))
    }

    func testMacBookWithExternalKeyboardListsBothWithNames() throws {
        let builtIn = #"{"Product":"Apple Internal Keyboard / Trackpad","VendorID":0,"Built-In":true,"IOClass":"AppleHIDKeyboardEventDriverV2","type":"service","PrimaryUsage":6,"PrimaryUsagePage":1,"IORegistryEntryID":4295398400,"Transport":"FIFO","LocationID":231,"ProductID":0}"#
        let external = #"{"Product":"cl80","VendorID":21577,"IOClass":"AppleUserHIDEventService","type":"service","PrimaryUsage":6,"PrimaryUsagePage":1,"IORegistryEntryID":4294972703,"Transport":"USB","LocationID":34673408,"ProductID":37148}"#
        let keyboards = try SessionCapsHIDUtilTransport.parseKeyboards(builtIn + "\n" + external + "\n")
        XCTAssertEqual(keyboards.map(\.name), ["Built-in keyboard", "cl80"])
        XCTAssertEqual(keyboards.map(\.device), try SessionCapsHIDUtilTransport.parseServices(builtIn + "\n" + external))
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.automaticSelection(devices: keyboards.map(\.device), boot: boot))

        let twin = external.replacingOccurrences(of: "4294972703", with: "4294972704")
            .replacingOccurrences(of: "34673408", with: "34677248")
        let twins = try SessionCapsHIDUtilTransport.parseKeyboards(external + "\n" + twin)
        XCTAssertEqual(twins.map(\.name), ["cl80 1", "cl80 2"])
        let unnamed = external.replacingOccurrences(of: #""Product":"cl80","#, with: "")
        XCTAssertEqual(try SessionCapsHIDUtilTransport.parseKeyboards(unnamed).map(\.name), ["Keyboard"])
    }

    // Exact `hidutil list --ndjson --matching keyboard` output from the mini,
    // 2026-10-19: Karabiner's DriverKit keyboard (LocationID 0) beside three USB keyboards.
    private let miniList = #"""
    {"IOUserClass":"AppleUserHIDEventDriver","VendorID":5824,"type":"service","IOClass":"AppleUserHIDEventService","Product":"Karabiner DriverKit VirtualHIDKeyboard 1.8.0","PrimaryUsagePage":1,"IORegistryEntryID":4294973376,"PrimaryUsage":6,"LocationID":0,"ProductID":10203}
    {"Product":"KeyPath Physical HID Fixture","VendorID":51966,"IOUserClass":"AppleUserHIDEventDriver","IOClass":"AppleUserHIDEventService","type":"service","PrimaryUsage":6,"PrimaryUsagePage":1,"IORegistryEntryID":4299842268,"Transport":"USB","LocationID":51445760,"ProductID":16400}
    {"Product":"X2A","VendorID":13652,"IOUserClass":"AppleUserHIDEventDriver","IOClass":"AppleUserHIDEventService","type":"service","PrimaryUsage":6,"PrimaryUsagePage":1,"IORegistryEntryID":4294972747,"Transport":"USB","LocationID":34677248,"ProductID":62727}
    {"Product":"cl80","VendorID":21577,"IOUserClass":"AppleUserHIDEventDriver","IOClass":"AppleUserHIDEventService","type":"service","PrimaryUsage":6,"PrimaryUsagePage":1,"IORegistryEntryID":4294972703,"Transport":"USB","LocationID":34673408,"ProductID":37148}
    {"IOClass":"AppleUserHIDDevice","VendorID":21577,"Product":"cl80","type":"device","PrimaryUsage":6,"LocationID":34673408,"IORegistryEntryID":4294972612,"ProductID":37148,"Transport":"USB","Manufacturer":"Vial","PrimaryUsagePage":1,"IOUserClass":"AppleUserUSBHostHIDDevice"}
    {"IOUserClass":"org_pqrs_Karabiner_DriverKit_VirtualHIDKeyboard","VendorID":5824,"Manufacturer":"pqrs.org","IOClass":"AppleUserHIDDevice","type":"device","Product":"Karabiner DriverKit VirtualHIDKeyboard 1.8.0","PrimaryUsagePage":1,"IORegistryEntryID":4294973367,"PrimaryUsage":6,"LocationID":0,"ProductID":10203}
    {"IOClass":"AppleUserHIDDevice","VendorID":13652,"Product":"X2A","type":"device","PrimaryUsage":6,"LocationID":34677248,"IORegistryEntryID":4294972634,"ProductID":62727,"Transport":"USB","Manufacturer":"pulsar","PrimaryUsagePage":1,"IOUserClass":"AppleUserUSBHostHIDDevice"}
    {"IOClass":"AppleUserHIDDevice","VendorID":51966,"Product":"KeyPath Physical HID Fixture","type":"device","PrimaryUsage":6,"LocationID":51445760,"IORegistryEntryID":4299842260,"ProductID":16400,"Transport":"USB","Manufacturer":"KeyPath Lab","PrimaryUsagePage":1,"IOUserClass":"AppleUserUSBHostHIDDevice"}
    """#
    private let cl80 = #"{"Product":"cl80","VendorID":21577,"IOUserClass":"AppleUserHIDEventDriver","IOClass":"AppleUserHIDEventService","type":"service","PrimaryUsage":6,"PrimaryUsagePage":1,"IORegistryEntryID":4294972703,"Transport":"USB","LocationID":34673408,"ProductID":37148}"#
    private let x2a = #"{"Product":"X2A","VendorID":13652,"IOUserClass":"AppleUserHIDEventDriver","IOClass":"AppleUserHIDEventService","type":"service","PrimaryUsage":6,"PrimaryUsagePage":1,"IORegistryEntryID":4294972747,"Transport":"USB","LocationID":34677248,"ProductID":62727}"#

    func testKarabinerVirtualKeyboardIsSkippedNotFatal() throws {
        let list = try SessionCapsHIDUtilTransport.parseKeyboardList(miniList)
        XCTAssertEqual(list.keyboards.map(\.name), ["KeyPath Physical HID Fixture", "X2A", "cl80"])
        XCTAssertEqual(list.withheld, 0)
        XCTAssertFalse(list.keyboards.contains { $0.device.vendorID == 5824 })
        // Only Karabiner's keyboard plus one USB board: that board is the only keyboard.
        let karabiner = String(miniList.split(separator: "\n")[0])
        let inventory = try SessionCapsHIDUtilTransport.parseInventory(karabiner + "\n" + cl80)
        XCTAssertEqual(inventory.withheld, 0)
        XCTAssertNoThrow(try SessionCapsRuntimeSupport.automaticSelection(devices: inventory.devices, withheld: inventory.withheld, boot: boot))
    }

    func testSharedLocatorWithholdsEverySharerButKeepsOtherKeyboards() throws {
        // One board exposing a second keyboard interface: same VID/PID/LocationID,
        // distinct event-service IDs. hidutil would select both, so neither is offered.
        let second = cl80.replacingOccurrences(of: "4294972703", with: "4294972704")
        let inventory = try SessionCapsHIDUtilTransport.parseInventory([cl80, second, x2a].joined(separator: "\n"))
        XCTAssertEqual(inventory.devices.map(\.registryEntryID), [4_294_972_747])
        XCTAssertEqual(inventory.withheld, 2)

        // A consented cl80 instance now refuses instead of leasing an ambiguous selector.
        let chosen = try XCTUnwrap(SessionCapsHIDUtilTransport.parseServices(cl80).first)
        let selection = SessionCapsSelection(device: chosen, bootSessionUUID: boot, reservesF18: true)
        XCTAssertThrowsError(try selection.verifyConnected(devices: inventory.devices, currentBoot: boot))
        // X2A is eligible but is not picked on the user's behalf beside an untargetable keyboard.
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.automaticSelection(devices: inventory.devices, withheld: inventory.withheld, boot: boot))

        // An unsupported service sharing a target's locator withholds that target too.
        let shadow = second.replacingOccurrences(of: "AppleUserHIDEventService", with: "SomeFutureEventService")
        XCTAssertEqual(try SessionCapsHIDUtilTransport.parseInventory(cl80 + "\n" + shadow), .init(devices: [], withheld: 2))
        // Distinct serial numbers disambiguate the same locator.
        let serialA = cl80.replacingOccurrences(of: #""Product""#, with: #""SerialNumber":"A","Product""#)
        let serialB = second.replacingOccurrences(of: #""Product""#, with: #""SerialNumber":"B","Product""#)
        XCTAssertEqual(try SessionCapsHIDUtilTransport.parseInventory(serialA + "\n" + serialB).devices.count, 2)
    }

    func testBrokenGrammarStillRefusesWholeList() {
        for bad in [miniList + "\n{", miniList + "\n" + #"{"type":"other"}"#,
                    miniList + "\n" + cl80.replacingOccurrences(of: "21577", with: "21577.5"),
                    miniList + "\n" + cl80.replacingOccurrences(of: #""PrimaryUsage":6,"#, with: "")]
        {
            XCTAssertThrowsError(try SessionCapsHIDUtilTransport.parseInventory(bad))
        }
    }

    @MainActor
    func testSettingsPrefersConnectedSavedChoiceElseOnlyKeyboard() {
        let other = SessionCapsMappingPolicy.DeviceIdentity(registryEntryID: 99, vendorID: 4321,
                                                            productID: 8765, serialNumber: nil, locationID: 456)
        XCTAssertEqual(SessionCapsSettingsSection.effectiveDevice(saved: device, connected: [other, device]), device)
        XCTAssertNil(SessionCapsSettingsSection.effectiveDevice(saved: nil, connected: [other, device]))
        XCTAssertNil(SessionCapsSettingsSection.effectiveDevice(saved: device, connected: [other, other]))
        XCTAssertEqual(SessionCapsSettingsSection.effectiveDevice(saved: device, connected: [other]), other)
        XCTAssertNil(SessionCapsSettingsSection.effectiveDevice(saved: nil, connected: []))
        XCTAssertNil(SessionCapsSettingsSection.effectiveDevice(saved: nil, connected: [other], withheld: 1))
        XCTAssertEqual(SessionCapsSettingsSection.effectiveDevice(saved: device, connected: [device], withheld: 1), device)
    }

    func testDecodeRejectsCorruptVersionAndUnknownConsentFields() throws {
        let selected = SessionCapsSelection(device: device, bootSessionUUID: boot, reservesF18: true)
        let data = try JSONEncoder().encode(selected)
        XCTAssertEqual(try SessionCapsSelection.decode(data, currentBoot: boot), selected)
        XCTAssertThrowsError(try SessionCapsSelection.decode(Data("{}".utf8), currentBoot: boot))
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        fields["version"] = 2
        XCTAssertThrowsError(try SessionCapsSelection.decode(JSONSerialization.data(withJSONObject: fields), currentBoot: boot))
        fields["version"] = 1
        fields["automaticallyRebind"] = true
        XCTAssertThrowsError(try SessionCapsSelection.decode(JSONSerialization.data(withJSONObject: fields), currentBoot: boot))
    }

    func testSharedSelectionRejectsDisconnectedInstanceInSameBoot() throws {
        let currentBoot = try SessionCapsRuntimeSupport.bootSessionUUID()
        let selected = SessionCapsSelection(device: device, bootSessionUUID: currentBoot, reservesF18: true)
        let data = try JSONEncoder().encode(selected)
        var lookedUp: [UInt64] = []
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.selectedDevice(
            environment: [:], selectionData: data, registryEntryExists: { id in
                lookedUp.append(id)
                return false
            }
        ))
        XCTAssertEqual(lookedUp, [device.registryEntryID])
        XCTAssertEqual(try SessionCapsRuntimeSupport.selectedDevice(
            environment: [:], selectionData: data, registryEntryExists: { _ in true }
        ), device)
        enum Unavailable: Error { case lookup }
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.selectedDevice(
            environment: [:], selectionData: data, registryEntryExists: { _ in throw Unavailable.lookup }
        ))
    }

    func testSharedSelectionAbsentOrStaleDoesNotInventConsent() throws {
        XCTAssertNil(try SessionCapsRuntimeSupport.selectedDevice(environment: [:], selectionData: nil))
        let stale = SessionCapsSelection(device: device, bootSessionUUID: UUID().uuidString, reservesF18: true)
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.selectedDevice(environment: [:], selectionData: JSONEncoder().encode(stale)))
    }
}
