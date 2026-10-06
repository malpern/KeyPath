import Darwin
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
        guard case let .invalid(reason) = disabled.result else { return XCTFail("Caps must require opt-in") }
        XCTAssertTrue(reason.contains("Settings > General"))
        XCTAssertFalse(reason.contains("driver backend"))
        XCTAssertFalse(disabled.managedCaps)
        let validatedDigest = try SessionCapsRuntimeSupport.configSHA256(file.path)
        let enabled = SessionCapsRuntimeSupport.validate(configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost, environment: environment)
        guard case .valid = enabled.result else { return XCTFail("Owned Caps profile should validate") }
        XCTAssertTrue(enabled.managedCaps)
        XCTAssertEqual(try SessionCapsRuntimeSupport.validatedConfigDigest(file.path, beforeValidation: validatedDigest), validatedDigest)
        try "(defsrc f18)(deflayer base a)".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.validatedConfigDigest(file.path, beforeValidation: validatedDigest))
        let ordinary = SessionCapsRuntimeSupport.validate(configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost, environment: environment)
        guard case .valid = ordinary.result else { return XCTFail("Ordinary native F18 profile should stay eligible") }
        XCTAssertFalse(ordinary.managedCaps)
        let stale = SessionCapsSelection(device: device, bootSessionUUID: UUID().uuidString, reservesF18: true)
        let staleData = try JSONEncoder().encode(stale)
        let ordinaryWithStaleConsent = SessionCapsRuntimeSupport.validate(configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost,
                                                                         environment: [:], selectionData: staleData)
        guard case .valid = ordinaryWithStaleConsent.result else { return XCTFail("Stale Caps consent must not block ordinary rules") }
        XCTAssertFalse(ordinaryWithStaleConsent.managedCaps)
        try "(defsrc caps)(deflayer base esc)".write(to: file, atomically: true, encoding: .utf8)
        let capsWithStaleConsent = SessionCapsRuntimeSupport.validate(configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost,
                                                                     environment: [:], selectionData: staleData)
        guard case .invalid = capsWithStaleConsent.result else { return XCTFail("Caps needs fresh consent") }
        XCTAssertFalse(capsWithStaleConsent.managedCaps)
        try "(defsrc caps)(deflayer base".write(to: file, atomically: true, encoding: .utf8)
        let malformed = SessionCapsRuntimeSupport.validate(configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost,
                                                           environment: [:], selectionData: nil)
        let malformedWithStaleConsent = SessionCapsRuntimeSupport.validate(configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost,
                                                                           environment: [:], selectionData: staleData)
        guard case let .invalid(parserReason) = malformed.result,
              case let .invalid(staleReason) = malformedWithStaleConsent.result else { return XCTFail("Malformed syntax must remain invalid") }
        XCTAssertEqual(staleReason, parserReason, "Stale consent must not replace the actual parser diagnosis")
        XCTAssertFalse(staleReason.contains("Settings > General"))
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

    func testPreviousBootRecoveryDoesNotCheckReusedLivePIDsOrOldDevice() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let device = SessionCapsMappingPolicy.DeviceIdentity(registryEntryID: 42, vendorID: 51966,
                                                             productID: 16400, serialNumber: nil, locationID: 123)
        let oldBoot = UUID().uuidString
        XCTAssertNotEqual(oldBoot, try SessionCapsRuntimeSupport.bootSessionUUID())
        // Both PIDs are live in this boot; previous-boot identity must be classified first.
        let owner = SessionCapsMappingPolicy.Owner(uid: getuid(), parentPID: getppid(), workerPID: getpid(),
                                                  nonce: "previous-boot", generation: "old", bootSessionUUID: oldBoot)
        let record = try SessionCapsMappingPolicy.acquire(original: [], device: device, devices: [device],
                                                          owner: owner, effectiveConfigSHA256: String(repeating: "a", count: 64))
        let journal = root.appendingPathComponent("caps-mapping-intent.json")
        let marker = root.appendingPathComponent("caps-mapping-mutation-in-flight.json")
        try JSONEncoder().encode(record).write(to: journal)
        try JSONEncoder().encode(owner).write(to: marker)
        chmod(journal.path, 0o600)
        chmod(marker.path, 0o600)
        try SessionCapsRuntimeSupport.recoverPending(directory: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testManagedDigestRejectsConfigurationChangedAcrossValidation() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("(defsrc caps)(deflayer base esc)".utf8).write(to: file)
        let before = try SessionCapsRuntimeSupport.configSHA256(file.path)
        XCTAssertEqual(try SessionCapsRuntimeSupport.validatedConfigDigest(file.path, beforeValidation: before), before)
        try Data("(defsrc caps)(deflayer base lctl)".utf8).write(to: file)
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.validatedConfigDigest(file.path, beforeValidation: before))
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.validatedConfigDigest(file.path, beforeValidation: nil))
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
