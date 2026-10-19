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
            XCTAssertThrowsError(try SessionCapsHIDUtilTransport.parseServices(bad))
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

    @MainActor
    func testSettingsPrefersConnectedSavedChoiceElseOnlyKeyboard() {
        let other = SessionCapsMappingPolicy.DeviceIdentity(registryEntryID: 99, vendorID: 4321,
                                                            productID: 8765, serialNumber: nil, locationID: 456)
        XCTAssertEqual(SessionCapsSettingsSection.effectiveDevice(saved: device, connected: [other, device]), device)
        XCTAssertNil(SessionCapsSettingsSection.effectiveDevice(saved: nil, connected: [other, device]))
        XCTAssertNil(SessionCapsSettingsSection.effectiveDevice(saved: device, connected: [other, other]))
        XCTAssertEqual(SessionCapsSettingsSection.effectiveDevice(saved: device, connected: [other]), other)
        XCTAssertNil(SessionCapsSettingsSection.effectiveDevice(saved: nil, connected: []))
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
