import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class SessionCapsIntermediateTests: XCTestCase {
    private typealias Policy = SessionCapsMappingPolicy
    private let caps: UInt64 = 30_064_771_129 // 0x700000039
    private let f20: UInt64 = 30_064_771_183 // 0x70000006F

    /// `hidutil property --get UserKeyMapping` on the mini, 2026-10-19, with
    /// Raycast's Hyper Key on Caps Lock: Caps -> F20 on every keyboard service.
    private let raycastOutput = """
    RegistryID  Key                   Value
    100000a5c   UserKeyMapping   (null)
    10000081f   UserKeyMapping   (null)
    1004a62dc   UserKeyMapping   (
            {
            HIDKeyboardModifierMappingDst = 30064771183;
            HIDKeyboardModifierMappingSrc = 30064771129;
        }
    )
    10000154b   UserKeyMapping   (
            {
            HIDKeyboardModifierMappingDst = 30064771183;
            HIDKeyboardModifierMappingSrc = 30064771129;
        }
    )
    """

    func testPoolIsTheFunctionKeysTheTapCanSee() {
        XCTAssertEqual(Set(SessionCapsIntermediate.pool), Set(104 ... 111))
        XCTAssertEqual(SessionCapsIntermediate.pool.first, 109, "F18 stays first for continuity")
        for usage in SessionCapsIntermediate.pool {
            // Every candidate round-trips through the session's own key map.
            let code = try? XCTUnwrap(SessionCapsIntermediate.keyCodes[usage])
            XCTAssertEqual(code.flatMap { SessionKeyMap.keyCodeToUsage[$0] }, usage)
        }
        XCTAssertFalse(SessionCapsIntermediate.isCandidate(112), "F21 has no macOS keycode")
        XCTAssertEqual(SessionCapsIntermediate.label(104), "F13")
        XCTAssertEqual(SessionCapsIntermediate.label(111), "F20")
        XCTAssertEqual(SessionCapsIntermediate.kanataName(110), "f19")
    }

    func testChoiceKeepsCurrentWhileFreeAndMovesWhenTaken() {
        let any: (UInt32) -> Bool = { _ in true }
        XCTAssertEqual(SessionCapsIntermediate.choose(preferred: nil, occupied: [], acceptsProfile: any), 109)
        XCTAssertEqual(SessionCapsIntermediate.choose(preferred: 104, occupied: [], acceptsProfile: any), 104)
        XCTAssertEqual(SessionCapsIntermediate.choose(preferred: 104, occupied: [104], acceptsProfile: any), 109)
        XCTAssertEqual(SessionCapsIntermediate.choose(preferred: 109, occupied: [], acceptsProfile: { $0 != 109 }), 110,
                       "A rule that uses F18 moves the reservation to F19")
        XCTAssertNil(SessionCapsIntermediate.choose(preferred: 109, occupied: Set(104 ... 110), acceptsProfile: { $0 != 111 }))
        XCTAssertEqual(SessionCapsIntermediate.choose(preferred: 57, occupied: [], acceptsProfile: any), 109,
                       "An invalid saved key is ignored, not honoured")
    }

    func testRaycastHyperKeyRowsOccupyF20() throws {
        let rows = try SessionCapsHIDUtilTransport.parseAllMappings(raycastOutput)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0x1_0000_0A5C], [])
        XCTAssertEqual(rows[0x1_004A_62DC], [.init(source: caps, destination: f20)])
        XCTAssertEqual(rows[0x1_0000_154B], [.init(source: caps, destination: f20)])
        let usages = rows.values.flatMap { $0.flatMap { [$0.source, $0.destination] } }
        XCTAssertEqual(SessionCapsIntermediate.occupied(mappingUsages: usages, shortcutKeyCodes: []), [111])
    }

    func testOccupancyReadsEveryServiceButNotKeyPathsOwnRow() throws {
        let own = Policy.DeviceIdentity(registryEntryID: 0x1_0000_0A5C, vendorID: 1, productID: 2,
                                        serialNumber: nil, locationID: 3)
        let output = """
        RegistryID  Key                   Value
        100000a5c   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        10000081f   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771076;
                HIDKeyboardModifierMappingSrc = 30064771176;
            }
        )
        """
        // KeyPath's live Caps -> F18 on its own keyboard is not "someone else's F18";
        // F13 (usage 104) used as a source on another keyboard is taken.
        let taken = try SessionCapsRuntimeSupport.occupiedIntermediates(own: own, run: { _ in output }, shortcutKeyCodes: { [] })
        XCTAssertEqual(taken, [104])
        let withoutOwner = try SessionCapsRuntimeSupport.occupiedIntermediates(own: nil, run: { _ in output }, shortcutKeyCodes: { [] })
        XCTAssertEqual(withoutOwner, [104, 109])
        // An enabled shortcut on F19's keycode (80) takes F19.
        let shortcut = try SessionCapsRuntimeSupport.occupiedIntermediates(own: own, run: { _ in output }, shortcutKeyCodes: { [80] })
        XCTAssertEqual(shortcut, [104, 110])
    }

    func testUnreadableMappingOutputIsAnErrorNotAFreeKey() {
        for bad in ["", "garbage", "RegistryID  Key  Value\n100000a5c   UserKeyMapping   (\n{ Unknown = 1; }\n)",
                    "RegistryID  Key  Value\n    {\n"]
        {
            XCTAssertThrowsError(try SessionCapsHIDUtilTransport.parseAllMappings(bad), bad)
        }
    }

    func testOnlyEnabledShortcutsCount() {
        let hotkeys: [String: Any] = [
            "118": ["enabled": false, "value": ["parameters": [65535, 18, 262_144], "type": "standard"]],
            "200": ["enabled": true, "value": ["parameters": [65535, 79, 0], "type": "standard"]],
            "201": ["enabled": true, "value": ["parameters": [65535], "type": "standard"]],
            "202": ["enabled": true],
        ]
        XCTAssertEqual(SessionCapsRuntimeSupport.parseShortcutKeyCodes(hotkeys), [79])
        XCTAssertEqual(SessionCapsIntermediate.occupied(mappingUsages: [], shortcutKeyCodes: [79]), [109])
    }

    func testRaycastHyperKeyIsNamedOnlyWhenItsSettingAgrees() {
        let row = [Policy.Mapping(source: caps, destination: f20)]
        let on = SessionCapsConflict.RaycastHyperKey(enabled: true, keyCode: 57)
        XCTAssertEqual(SessionCapsConflict.identify(row, raycast: on), .raycastHyperKey)
        XCTAssertTrue(SessionCapsConflict.raycastHyperKey.message.contains("Raycast"))
        // Same row, but Raycast says Hyper Key is off or on another key: not named.
        for raycast in [nil, .init(enabled: false, keyCode: 57), .init(enabled: true, keyCode: 63)] as [SessionCapsConflict.RaycastHyperKey?] {
            XCTAssertEqual(SessionCapsConflict.identify(row, raycast: raycast), .unknown(destination: f20))
        }
        // Raycast on, but this keyboard's Caps goes somewhere else.
        XCTAssertEqual(SessionCapsConflict.identify([.init(source: caps, destination: 0x7_0000_00E0)], raycast: on),
                       .unknown(destination: 0x7_0000_00E0))
        XCTAssertNil(SessionCapsConflict.identify([.init(source: 0x7_0000_0004, destination: f20)], raycast: on))
        XCTAssertNil(SessionCapsConflict.identify([], raycast: on))
    }

    func testUnknownOwnerMessagesSayWhatCanBeKnown() {
        XCTAssertTrue(SessionCapsConflict.unknown(destination: f20).message.contains("(to F20)"))
        let modifier = SessionCapsConflict.unknown(destination: 0x7_0000_00E0).message
        XCTAssertTrue(modifier.contains("Modifier Keys"))
        XCTAssertFalse(modifier.contains("Raycast"))
    }

    @MainActor
    func testSettingsDoesNotReportKeyPathsOwnRowAsAConflict() {
        let own = SessionCapsConflict.unknown(destination: Policy.packed(110))
        XCTAssertTrue(SessionCapsSettingsSection.ownRow(own, intermediate: 110))
        XCTAssertFalse(SessionCapsSettingsSection.ownRow(own, intermediate: 109))
        XCTAssertFalse(SessionCapsSettingsSection.ownRow(.raycastHyperKey, intermediate: 109))
        XCTAssertTrue(SessionCapsSettingsSection.ownRow(.raycastHyperKey, intermediate: 111))
        XCTAssertFalse(SessionCapsSettingsSection.ownRow(own, intermediate: nil))
    }

    func testConflictReadsTheChosenKeyboardOnly() throws {
        let device = Policy.DeviceIdentity(registryEntryID: 0x1_004A_62DC, vendorID: 1, productID: 2,
                                           serialNumber: nil, locationID: 3)
        let block = "RegistryID Key Value\n1004a62dc UserKeyMapping (\n{\nHIDKeyboardModifierMappingDst = 30064771183;\nHIDKeyboardModifierMappingSrc = 30064771129;\n}\n)"
        var asked: [[String]] = []
        let backend = SessionCapsHIDUtilTransport.backend { arguments in
            asked.append(arguments)
            return block
        }
        let conflict = try SessionCapsRuntimeSupport.capsConflict(on: device, backend: backend,
                                                                  raycast: .init(enabled: true, keyCode: 57))
        XCTAssertEqual(conflict, .raycastHyperKey)
        XCTAssertEqual(asked, try [SessionCapsHIDUtilTransport.readArguments(device)])
    }

    @MainActor
    func testRefusalMessageNamesRaycastOrStaysGeneric() {
        let message = ServiceLifecycleCoordinator.sessionFailureRecoveryMessage("managed-caps-activation-refused: capsAlreadyMapped")
        XCTAssertTrue(message.contains("Caps Lock"), message)
    }

    /// The runtime may emit F18 once F19 is reserved; only the lease's own
    /// intermediate stops the session.
    func testWorkerBackstopFollowsTheLeasedIntermediate() throws {
        let device = Policy.DeviceIdentity(registryEntryID: 42, vendorID: 0x303A, productID: 0x4002,
                                           serialNumber: "fixture-1", locationID: 123)
        let owner = Policy.Owner(uid: 502, parentPID: 100, workerPID: 101, nonce: "n", generation: "g",
                                 bootSessionUUID: "A7B944DF-471A-4C22-B9F3-A4EE5522F775")
        let record = try Policy.acquire(original: [], device: device, devices: [device], owner: owner,
                                        effectiveConfigSHA256: String(repeating: "a", count: 64),
                                        intermediate: Policy.packed(110))
        XCTAssertTrue(SessionRuntimeWorker.emitsReservedKey(usagePage: 7, usage: 110, record: record))
        XCTAssertFalse(SessionRuntimeWorker.emitsReservedKey(usagePage: 7, usage: 109, record: record))
        XCTAssertFalse(SessionRuntimeWorker.emitsReservedKey(usagePage: 12, usage: 110, record: record))
        XCTAssertFalse(SessionRuntimeWorker.emitsReservedKey(usagePage: 7, usage: 110, record: nil))
    }

    /// A launch that declined managed Caps says so; the worker must not pick
    /// up the saved selection behind the app's back.
    func testExplicitNoSelectionNeverFallsBackToTheSavedOne() throws {
        let device = Policy.DeviceIdentity(registryEntryID: 42, vendorID: 1234, productID: 5678,
                                           serialNumber: nil, locationID: 123)
        let saved = try JSONEncoder().encode(SessionCapsSelection(device: device, bootSessionUUID: SessionCapsRuntimeSupport.bootSessionUUID(),
                                                                  intermediateUsage: 104))
        let none = [SessionCapsRuntimeSupport.selectionEnvironmentKey: SessionCapsRuntimeSupport.noSelection]
        XCTAssertNil(try SessionCapsRuntimeSupport.selected(environment: none, selectionData: saved, registryEntryExists: { _ in true }))
        XCTAssertEqual(SessionCapsRuntimeSupport.preferredIntermediate(environment: none, selectionData: saved), 109)
        XCTAssertEqual(try SessionCapsRuntimeSupport.selected(environment: [:], selectionData: saved, registryEntryExists: { _ in true })?.device, device)
        XCTAssertEqual(SessionCapsRuntimeSupport.preferredIntermediate(environment: [:], selectionData: saved), 104)
    }

    /// Regression (Air, 2026-10-19): `keypath-cli rule add f18 f20 --apply`
    /// reloaded a profile using F18 into a session that still reserved F18.
    /// The session now judges a reloaded profile against its own lease.
    func testReloadedProfileMustStillFitTheLeasedKey() throws {
        let device = Policy.DeviceIdentity(registryEntryID: 42, vendorID: 0x303A, productID: 0x4002,
                                           serialNumber: "fixture-1", locationID: 123)
        let owner = Policy.Owner(uid: 502, parentPID: 100, workerPID: 101, nonce: "n", generation: "g",
                                 bootSessionUUID: "A7B944DF-471A-4C22-B9F3-A4EE5522F775")
        let f18Lease = try Policy.acquire(original: [], device: device, devices: [device], owner: owner,
                                          effectiveConfigSHA256: String(repeating: "a", count: 64))
        typealias Admission = SessionCapsRuntimeSupport.Admission
        XCTAssertTrue(SessionRuntimeWorker.profileFitsLease(Admission(result: .valid, managedCaps: true, intermediateUsage: 109), record: f18Lease))
        // The profile now uses F18: admission without re-choice refuses, or
        // (with re-choice) lands on another key. Either way the lease no longer fits.
        XCTAssertFalse(SessionRuntimeWorker.profileFitsLease(Admission(result: .invalid(reason: "uses f18"), managedCaps: false, intermediateUsage: 109), record: f18Lease))
        XCTAssertFalse(SessionRuntimeWorker.profileFitsLease(Admission(result: .valid, managedCaps: true, intermediateUsage: 110), record: f18Lease))
        // The Caps rule was removed: an ordinary profile also needs a restart.
        XCTAssertFalse(SessionRuntimeWorker.profileFitsLease(Admission(result: .valid, managedCaps: false, intermediateUsage: 109), record: f18Lease))
    }

    @MainActor
    func testStartupBannerUsesTheSameWordingAsSettings() {
        let f20 = SessionCapsConflict.unknown(destination: 0x7_0000_006F)
        XCTAssertEqual(ServiceLifecycleCoordinator.capsConflictMessage(conflict: f20, raycast: nil), f20.message)
        XCTAssertTrue(ServiceLifecycleCoordinator.capsConflictMessage(conflict: f20, raycast: nil).contains("(to F20)"))
        XCTAssertEqual(ServiceLifecycleCoordinator.capsConflictMessage(conflict: .raycastHyperKey, raycast: nil),
                       SessionCapsConflict.raycastHyperKey.message)
        // Row unreadable: Raycast's own setting still names it.
        XCTAssertEqual(ServiceLifecycleCoordinator.capsConflictMessage(conflict: nil, raycast: .init(enabled: true, keyCode: 57)),
                       SessionCapsConflict.raycastHyperKey.message)
        XCTAssertTrue(ServiceLifecycleCoordinator.capsConflictMessage(conflict: nil, raycast: nil).contains("Modifier Keys"))
    }
}
