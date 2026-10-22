import CoreGraphics
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
        // Without consent Caps is never managed (nothing is mapped). The
        // profile still runs, with Caps Lock passing through: paused.
        let disabled = SessionCapsRuntimeSupport.admit(configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost, environment: [:])
        guard case .valid = disabled.result else { return XCTFail("A Caps profile without consent runs paused") }
        XCTAssertFalse(disabled.managedCaps)
        XCTAssertTrue(disabled.capsPaused)
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
        let stale = SessionCapsSelection(device: device, bootSessionUUID: UUID().uuidString)
        let staleData = try JSONEncoder().encode(stale)
        let ordinaryWithStaleConsent = SessionCapsRuntimeSupport.validate(configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost,
                                                                          environment: [:], selectionData: staleData)
        guard case .valid = ordinaryWithStaleConsent.result else { return XCTFail("Stale Caps consent must not block ordinary rules") }
        XCTAssertFalse(ordinaryWithStaleConsent.managedCaps)
        try "(defsrc caps)(deflayer base esc)".write(to: file, atomically: true, encoding: .utf8)
        let capsWithStaleConsent = SessionCapsRuntimeSupport.admit(configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost,
                                                                   environment: [:], selectionData: staleData)
        guard case .valid = capsWithStaleConsent.result else { return XCTFail("Stale consent pauses Caps, not the profile") }
        XCTAssertFalse(capsWithStaleConsent.managedCaps, "Caps needs fresh consent")
        XCTAssertTrue(capsWithStaleConsent.capsPaused)
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

    func testFirstTourRuleCanReachAutomaticSetupWithoutAnExistingSelection() throws {
        try SessionBridgeTestFixture.requireAvailable()
        let defaults = UserDefaults.standard
        let key = SessionCapsRuntimeSupport.automaticSetupDisabledKey
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.removeObject(forKey: key)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try "(defsrc caps)(deflayer base (tap-hold-press 200 200 esc caps))"
            .write(to: file, atomically: true, encoding: .utf8)
        let eligible = SessionCapsRuntimeSupport.validate(
            configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost,
            environment: [:], selectionData: nil, requireSelection: false
        )
        guard case .valid = eligible.result else { return XCTFail("First tour rule must reach automatic keyboard setup") }
        XCTAssertTrue(eligible.managedCaps)
        // Admission does not authorize the worker to manage Caps without a
        // verified selection; it runs the rest of the profile with Caps paused.
        let worker = SessionCapsRuntimeSupport.admit(
            configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost,
            environment: [:], selectionData: nil
        )
        guard case .valid = worker.result else { return XCTFail("Worker runs the profile with Caps paused") }
        XCTAssertFalse(worker.managedCaps, "Worker must still require a selection to manage Caps")
        XCTAssertTrue(worker.capsPaused)
        defaults.set(true, forKey: key)
        let disabled = SessionCapsRuntimeSupport.admit(
            configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost,
            environment: [:], selectionData: nil, requireSelection: false
        )
        XCTAssertFalse(disabled.managedCaps, "Explicit opt-out must remain respected")
        XCTAssertTrue(disabled.capsPaused, "Opt-out pauses Caps rules; the other rules still run")
    }

    /// A rule that uses the saved intermediate, or another app that took it,
    /// moves the reservation; the worker never moves it on its own.
    func testAdmissionMovesTheIntermediateAwayFromRulesAndOccupiedKeys() throws {
        try SessionBridgeTestFixture.requireAvailable()
        let defaults = UserDefaults.standard
        let key = SessionCapsRuntimeSupport.automaticSetupDisabledKey
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.removeObject(forKey: key)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let device = SessionCapsMappingPolicy.DeviceIdentity(registryEntryID: 42, vendorID: 51966, productID: 16400,
                                                             serialNumber: nil, locationID: 123)
        let boot = try SessionCapsRuntimeSupport.bootSessionUUID()
        func saved(_ usage: UInt32) throws -> Data {
            try JSONEncoder().encode(SessionCapsSelection(device: device, bootSessionUUID: boot, intermediateUsage: usage))
        }
        func admit(_ data: Data?, occupied: Set<UInt32> = [], rechoose: Bool = true) -> SessionCapsRuntimeSupport.Admission {
            SessionCapsRuntimeSupport.admit(configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost,
                                            environment: [:], selectionData: data, requireSelection: false,
                                            occupied: occupied, rechoose: rechoose)
        }

        try "(defsrc caps f18)(deflayer base esc a)".write(to: file, atomically: true, encoding: .utf8)
        let moved = try admit(saved(109))
        guard case .valid = moved.result else { return XCTFail("A rule on F18 must move the reservation, not refuse") }
        XCTAssertTrue(moved.managedCaps)
        XCTAssertEqual(moved.intermediateUsage, 110)
        XCTAssertEqual(try admit(saved(109), occupied: [110]).intermediateUsage, 111)
        guard case .invalid = try admit(saved(109), rechoose: false).result else {
            return XCTFail("The worker runs exactly the parent's key")
        }

        try "(defsrc caps)(deflayer base esc)".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(try admit(saved(104)).intermediateUsage, 104, "A free saved key is kept")
        XCTAssertEqual(admit(nil).intermediateUsage, 109)
        XCTAssertEqual(try admit(saved(104), occupied: [104]).intermediateUsage, 109)
        let full = try admit(saved(109), occupied: Set(SessionCapsIntermediate.pool))
        guard case let .invalid(reason) = full.result else { return XCTFail("No free key must refuse") }
        XCTAssertTrue(reason.contains("F13"), reason)
        XCTAssertFalse(full.managedCaps)
    }

    func testPhysicalAllUpRefusesAnyHeldKeyButCapsLatch() throws {
        XCTAssertNoThrow(try SessionCapsRuntimeSupport.requirePhysicalAllUp(isDown: { _ in false }))
        // Caps Lock's latch persists while it is not pressed; it never blocks.
        XCTAssertNoThrow(try SessionCapsRuntimeSupport.requirePhysicalAllUp(isDown: { $0 == 57 }))
        XCTAssertThrowsError(try SessionCapsRuntimeSupport.requirePhysicalAllUp(isDown: { $0 == 49 })) { error in
            XCTAssertEqual(error as? SessionCapsRuntimeSupport.Refusal, .physicalKeysHeld)
        }
        XCTAssertEqual(SessionCapsRuntimeSupport.heldKeys(isDown: { [49, 57, 0].contains($0) }), [0, 49])
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
