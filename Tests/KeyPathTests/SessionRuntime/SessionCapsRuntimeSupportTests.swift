import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class SessionCapsRuntimeSupportTests: XCTestCase {
    func testSelectionRequiresExplicitNativeF18Reservation() throws {
        let device = SessionCapsMappingPolicy.DeviceIdentity(registryEntryID: 42, vendorID: 51966, productID: 16400,
                                                             serialNumber: nil, locationID: 123)
        let raw = try String(decoding: JSONEncoder().encode(device), as: UTF8.self)
        XCTAssertNil(try SessionCapsRuntimeSupport.experimentalDevice(environment: [:]))
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.experimentalDevice(environment: ["KEYPATH_EXPERIMENTAL_MANAGED_CAPS_DEVICE": raw]))
        XCTAssertEqual(try SessionCapsRuntimeSupport.experimentalDevice(environment: [
            "KEYPATH_EXPERIMENTAL_MANAGED_CAPS_DEVICE": raw, "KEYPATH_EXPERIMENTAL_MANAGED_CAPS_RESERVE_F18": "1"
        ]), device)
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.experimentalDevice(environment: [
            "KEYPATH_EXPERIMENTAL_MANAGED_CAPS_DEVICE": "{}", "KEYPATH_EXPERIMENTAL_MANAGED_CAPS_RESERVE_F18": "1"
        ]))
    }

    func testActualProfileAdmissionKeepsOptInAndOrdinaryModesSeparate() throws {
        try SessionBridgeTestFixture.requireAvailable()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("caps.kbd")
        let device = SessionCapsMappingPolicy.DeviceIdentity(registryEntryID: 42, vendorID: 51966, productID: 16400,
                                                             serialNumber: nil, locationID: 123)
        let environment = try ["KEYPATH_EXPERIMENTAL_MANAGED_CAPS_DEVICE": String(decoding: JSONEncoder().encode(device), as: UTF8.self),
                               "KEYPATH_EXPERIMENTAL_MANAGED_CAPS_RESERVE_F18": "1"]
        try "(defsrc caps)(deflayer base esc)".write(to: file, atomically: true, encoding: .utf8)
        let disabled = SessionCapsRuntimeSupport.validate(configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost, environment: [:])
        guard case .invalid = disabled.result else { return XCTFail("Caps must require opt-in") }
        XCTAssertFalse(disabled.managedCaps)
        let enabled = SessionCapsRuntimeSupport.validate(configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost, environment: environment)
        guard case .valid = enabled.result else { return XCTFail("Owned Caps profile should validate") }
        XCTAssertTrue(enabled.managedCaps)
        try "(defsrc f18)(deflayer base a)".write(to: file, atomically: true, encoding: .utf8)
        let ordinary = SessionCapsRuntimeSupport.validate(configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost, environment: environment)
        guard case .valid = ordinary.result else { return XCTFail("Ordinary native F18 profile should stay eligible") }
        XCTAssertFalse(ordinary.managedCaps)
    }

    func testOrphanMutationMarkerBlocksRecoveryEvenWithoutIntent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("caps-mapping-mutation-in-flight.json")
        try Data("uncertain writer".utf8).write(to: marker)
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.recoverPending(directory: root)) { error in
            XCTAssertEqual(error as? SessionCapsMappingLease.Refusal, .mutationUncertain)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    func testConfigDigestRefusesSymlinkAndOversizedInput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("caps.kbd")
        try Data("(defsrc caps)(deflayer base esc)".utf8).write(to: file)
        XCTAssertEqual(try SessionCapsRuntimeSupport.configSHA256(file.path).count, 64)
        let link = root.appendingPathComponent("link.kbd")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.configSHA256(link.path))
        try Data(repeating: 65, count: 65537).write(to: file)
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.configSHA256(file.path))
    }
}
