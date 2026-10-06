import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class SessionCapsSelectionTests: XCTestCase {
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

    func testSharedSelectionAbsentOrStaleDoesNotInventConsent() throws {
        XCTAssertNil(try SessionCapsRuntimeSupport.selectedDevice(environment: [:], selectionData: nil))
        let stale = SessionCapsSelection(device: device, bootSessionUUID: UUID().uuidString, reservesF18: true)
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.selectedDevice(environment: [:], selectionData: JSONEncoder().encode(stale)))
    }
}
