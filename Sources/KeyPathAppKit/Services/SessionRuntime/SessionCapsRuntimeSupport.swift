import Carbon
import CryptoKit
import Darwin
import Foundation
import KeyPathCore

/// Caps consent and recovery shared by the existing lifecycle and worker.
/// Session events cannot distinguish another keyboard's native press of the
/// intermediate key: the reservation is an eligibility declaration, never a
/// device-attribution claim.
enum SessionCapsRuntimeSupport {
    typealias Policy = SessionCapsMappingPolicy
    enum Refusal: Error { case selection, bootIdentity, physicalKeysHeld, configIdentity, liveOwner }

    static func experimentalDevice(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Policy.DeviceIdentity? {
        #if DEBUG
            guard let raw = environment["KEYPATH_EXPERIMENTAL_MANAGED_CAPS_DEVICE"] else { return nil }
            guard environment["KEYPATH_EXPERIMENTAL_MANAGED_CAPS_RESERVE_F18"] == "1", raw.utf8.count <= 4096 else { throw Refusal.selection }
            let device = try JSONDecoder().decode(Policy.DeviceIdentity.self, from: Data(raw.utf8))
            _ = try SessionCapsHIDUtilTransport.selector(device)
            return device
        #else
            return nil
        #endif
    }

    /// Worker failure meaning "the reloaded profile needs a restart": it
    /// uses the reserved key, or no longer runs as managed Caps.
    static let profileChangedReason = "managed-caps-profile-changed"

    /// One tick of the reconnect watcher for a kept (displaced) choice.
    enum ReconnectState: Equatable {
        /// Its keyboard is back at the same port: restart onto it.
        case back
        /// The choice belongs to an earlier boot: forget it and stop watching.
        case stale
        /// Not back yet, or nothing could be read this tick: look again.
        case waiting
    }

    /// Unreadable boot identity or inventory waits rather than giving up:
    /// one failed read must not end the watch, and never re-binds.
    static func reconnectState(displaced: Data, boot: String?,
                               devices: () throws -> [Policy.DeviceIdentity]) -> ReconnectState
    {
        guard let boot else { return .waiting }
        guard (try? SessionCapsSelection.decode(displaced, currentBoot: boot)) != nil else { return .stale }
        guard let devices = try? devices() else { return .waiting }
        return reboundSelection(selectionData: displaced, devices: devices, boot: boot) != nil ? .back : .waiting
    }

    /// Worker failure meaning the leased keyboard instance is gone. Its
    /// mapping went with it; the app restarts without managed Caps.
    static let keyboardDisconnectedReason = "managed-caps-keyboard-disconnected"
    static let ownershipLostReason = "managed-caps-ownership-lost"
    /// Display name of the chosen keyboard, kept so messages can name it
    /// after it disconnects. Never used to identify a device.
    static let selectionNameKey = "keypath.session.caps.selection.name.v1"
    static let automaticSetupDisabledKey = "keypath.session.caps.automatic.disabled"
    static let selectionKey = "keypath.session.caps.selection.v1"
    static let selectionEnvironmentKey = "KEYPATH_SESSION_CAPS_SELECTION"
    /// What the app passes when it launched the worker without managed Caps.
    /// The worker then never falls back to the saved selection, which the
    /// app may have declined (for example when no intermediate was free).
    static let noSelection = "none"

    private static func selectionSource(_ environment: [String: String], _ selectionData: Data?) -> Data? {
        guard let passed = environment[selectionEnvironmentKey] else { return selectionData }
        return passed == noSelection ? nil : Data(passed.utf8)
    }

    static func selectedDevice(environment: [String: String] = ProcessInfo.processInfo.environment,
                               selectionData: Data? = UserDefaults.standard.data(forKey: selectionKey),
                               registryEntryExists: (UInt64) throws -> Bool = SessionCapsHIDUtilTransport.registryEntryExists) throws -> Policy.DeviceIdentity?
    {
        try selected(environment: environment, selectionData: selectionData, registryEntryExists: registryEntryExists)?.device
    }

    static func selected(environment: [String: String] = ProcessInfo.processInfo.environment,
                         selectionData: Data? = UserDefaults.standard.data(forKey: selectionKey),
                         registryEntryExists: (UInt64) throws -> Bool = SessionCapsHIDUtilTransport.registryEntryExists) throws -> SessionCapsSelection?
    {
        #if DEBUG
            if environment["KEYPATH_EXPERIMENTAL_MANAGED_CAPS_DEVICE"] != nil {
                return try experimentalDevice(environment: environment).map {
                    try SessionCapsSelection(device: $0, bootSessionUUID: bootSessionUUID())
                }
            }
        #endif
        guard let data = selectionSource(environment, selectionData) else { return nil }
        let selection = try SessionCapsSelection.decode(data, currentBoot: bootSessionUUID())
        // Boot-valid consent still belongs to one registry instance. Let the
        // existing automatic-setup policy rediscover after a disconnect instead
        // of passing a stale registry ID to the next worker.
        guard try registryEntryExists(selection.device.registryEntryID) else { throw Refusal.selection }
        return selection
    }

    /// The saved (or launch-supplied) intermediate, without verifying the
    /// keyboard is connected. Used only to order the choice.
    static func preferredIntermediate(environment: [String: String] = ProcessInfo.processInfo.environment,
                                      selectionData: Data? = UserDefaults.standard.data(forKey: selectionKey)) -> UInt32
    {
        #if DEBUG
            if environment["KEYPATH_EXPERIMENTAL_MANAGED_CAPS_DEVICE"] != nil { return SessionCapsIntermediate.defaultUsage }
        #endif
        let data = selectionSource(environment, selectionData)
        guard let data, let boot = try? bootSessionUUID(),
              let selection = try? SessionCapsSelection.decode(data, currentBoot: boot)
        else {
            return SessionCapsIntermediate.defaultUsage
        }
        return selection.intermediateUsage
    }

    static func validate(configPath: String, runtimeHost: KanataRuntimeHost,
                         environment: [String: String] = ProcessInfo.processInfo.environment,
                         selectionData: Data? = UserDefaults.standard.data(forKey: selectionKey),
                         requireSelection: Bool = true) -> (result: KanataHostBridgeValidationResult, managedCaps: Bool)
    {
        let admission = admit(configPath: configPath, runtimeHost: runtimeHost, environment: environment,
                              selectionData: selectionData, requireSelection: requireSelection)
        return (admission.result, admission.managedCaps)
    }

    struct Admission: Sendable {
        let result: KanataHostBridgeValidationResult
        let managedCaps: Bool
        /// The intermediate the profile was admitted with. It differs from the
        /// saved one when the profile or `occupied` took the saved key.
        let intermediateUsage: UInt32
        /// The profile needs managed Caps but no keyboard is usable (none
        /// chosen, the chosen one disconnected, or setup is off). It runs
        /// with Caps Lock passing through unchanged; its other rules work.
        var capsPaused = false
    }

    /// `occupied` names keys something else already uses (see
    /// `occupiedIntermediates`). With `rechoose`, a saved intermediate the
    /// profile uses or that is occupied is replaced by the next free one; the
    /// worker passes false so it runs exactly the key its parent chose.
    static func admit(configPath: String, runtimeHost: KanataRuntimeHost,
                      environment: [String: String] = ProcessInfo.processInfo.environment,
                      selectionData: Data? = UserDefaults.standard.data(forKey: selectionKey),
                      requireSelection: Bool = true, occupied: Set<UInt32> = [], rechoose: Bool = true) -> Admission
    {
        let usages = SessionKeyMap.keyCodeToUsage.values.filter { $0 != 57 }.sorted()
        let preferred = preferredIntermediate(environment: environment, selectionData: selectionData)
        let legacy = KanataHostBridge.validateSessionConfig(runtimeHost: runtimeHost, configPath: configPath, supportedUsages: usages)
        if case .valid = legacy { return Admission(result: legacy, managedCaps: false, intermediateUsage: preferred) }
        // Parse eligibility before consent so stale setup cannot disguise an
        // unrelated syntax or unsupported-action error. This acquires no mapping.
        var checked: [UInt32: KanataHostBridgeValidationResult] = [:]
        func managed(_ usage: UInt32) -> KanataHostBridgeValidationResult {
            if let result = checked[usage] { return result }
            let result = KanataHostBridge.validateSessionConfig(runtimeHost: runtimeHost, configPath: configPath,
                                                                supportedUsages: usages, managedCaps: true,
                                                                reservedUsage: usage)
            checked[usage] = result
            return result
        }
        var chosen = preferred
        let preferredValid = if case .valid = managed(preferred) { true } else { false }
        // Only a profile with physical Caps can be managed; skip re-parsing
        // every candidate for one that failed for another reason.
        let mentionsCaps = !preferredValid
            && ((try? String(contentsOfFile: configPath, encoding: .utf8))?.lowercased().contains("caps") ?? true)
        if rechoose, mentionsCaps || occupied.contains(preferred) {
            // A rule that uses the saved key, or another app that took it,
            // moves the reservation instead of refusing the profile.
            if let next = SessionCapsIntermediate.choose(preferred: preferred, occupied: occupied, acceptsProfile: {
                if case .valid = managed($0) { true } else { false }
            }) {
                chosen = next
            } else if preferredValid {
                return Admission(result: .invalid(reason: "every key KeyPath can reserve for Caps Lock (F13\u{2013}F20) is already in use by your rules, another app, or a keyboard shortcut"),
                                 managedCaps: false, intermediateUsage: preferred)
            }
        }
        let canManage = (!requireSelection && !UserDefaults.standard.bool(forKey: automaticSetupDisabledKey))
            || (try? selected(environment: environment, selectionData: selectionData)) != nil
        if canManage {
            guard case .valid = managed(chosen) else { return Admission(result: legacy, managedCaps: false, intermediateUsage: preferred) }
            return Admission(result: .valid, managedCaps: true, intermediateUsage: chosen)
        }
        // No usable keyboard. Physical Caps Lock is never mapped, so no key is
        // reserved; the profile only has to parse under some candidate.
        let parses = if case .valid = managed(chosen) { true } else {
            SessionCapsIntermediate.choose(preferred: preferred, occupied: [], acceptsProfile: {
                if case .valid = managed($0) { true } else { false }
            }) != nil
        }
        guard parses else { return Admission(result: legacy, managedCaps: false, intermediateUsage: preferred) }
        return Admission(result: .valid, managedCaps: false, intermediateUsage: preferred, capsPaused: true)
    }

    /// Pool keys already used elsewhere: in any keyboard service's
    /// UserKeyMapping (either side) or by an enabled macOS keyboard shortcut.
    /// KeyPath's own Caps row on `own` is not counted. Synchronous; call off
    /// the main actor.
    static func occupiedIntermediates(own: Policy.DeviceIdentity? = nil,
                                      run: ([String]) throws -> String = SessionCapsHIDUtilTransport.runHIDUtil,
                                      shortcutKeyCodes: () -> Set<UInt16> = enabledShortcutKeyCodes,
                                      emitsKeyboardUsages: (UInt64) -> Bool? = SessionCapsHIDUtilTransport.serviceEmitsKeyboardUsages) throws -> Set<UInt32>
    {
        let rows = try SessionCapsHIDUtilTransport.parseAllMappings(run(["property", "--get", "UserKeyMapping"]))
        // Our lease covers the chosen keyboard's service group (see
        // `SessionCapsHIDUtilTransport.serviceGroup`), so its Caps row on any
        // member is ours; on any other service it is not. Without the device
        // list, fall back to the chosen service.
        var ownServices = Set<UInt64>()
        if let own {
            ownServices = (try? SessionCapsHIDUtilTransport.groupMembers(own, run: run, emitsKeyboardUsages: emitsKeyboardUsages))
                ?? [own.registryEntryID]
        }
        var usages: [UInt64] = []
        for (registry, mappings) in rows {
            for mapping in mappings {
                if ownServices.contains(registry), mapping.source == Policy.caps,
                   SessionCapsIntermediate.isCandidate(packed: mapping.destination) { continue }
                usages += [mapping.source, mapping.destination]
            }
        }
        return SessionCapsIntermediate.occupied(mappingUsages: usages, shortcutKeyCodes: shortcutKeyCodes())
    }

    /// Virtual keycodes of enabled entries in System Settings > Keyboard >
    /// Keyboard Shortcuts (`com.apple.symbolichotkeys`), any modifiers.
    static func enabledShortcutKeyCodes() -> Set<UInt16> {
        guard let hotkeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                                      "com.apple.symbolichotkeys" as CFString) as? [String: Any]
        else { return [] }
        return parseShortcutKeyCodes(hotkeys)
    }

    static func parseShortcutKeyCodes(_ hotkeys: [String: Any]) -> Set<UInt16> {
        var codes = Set<UInt16>()
        for case let entry as [String: Any] in hotkeys.values {
            guard (entry["enabled"] as? NSNumber)?.boolValue == true,
                  let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [NSNumber], parameters.count >= 2,
                  let code = UInt16(exactly: parameters[1].intValue) else { continue }
            codes.insert(code)
        }
        return codes
    }

    /// Raycast's Hyper Key preference, when Raycast has one.
    static func raycastHyperKey() -> SessionCapsConflict.RaycastHyperKey? {
        guard let state = CFPreferencesCopyAppValue("raycast_hyperKey_state" as CFString,
                                                    "com.raycast.macos" as CFString) as? [String: Any] else { return nil }
        return .init(enabled: (state["enabled"] as? NSNumber)?.boolValue == true,
                     keyCode: (state["keyCode"] as? NSNumber)?.intValue)
    }

    /// Who already maps Caps Lock on this keyboard, if anyone. Synchronous;
    /// call off the main actor.
    static func capsConflict(on device: Policy.DeviceIdentity,
                             backend: SessionCapsMappingLease.Backend = SessionCapsHIDUtilTransport.backend(),
                             raycast: SessionCapsConflict.RaycastHyperKey? = raycastHyperKey()) throws -> SessionCapsConflict?
    {
        // Another tool may have mapped Caps on only one covered interface of
        // the board. Other interfaces (consumer, raw HID) are not read.
        let members = try backend.members(device)
        var rows = try [backend.read(device).mappings]
        if members.count > 1 {
            let group = try backend.readGroup(device)
            rows += members.sorted().filter { $0 != device.registryEntryID }.compactMap { group[$0] }
        }
        for mappings in rows {
            if let conflict = SessionCapsConflict.identify(mappings, raycast: raycast) { return conflict }
        }
        return nil
    }

    /// The saved choice re-bound to its keyboard replugged at the same port
    /// (see `SessionCapsSelection.rebound`), or nil.
    static func reboundSelection(selectionData: Data?, devices: [Policy.DeviceIdentity], boot: String) -> SessionCapsSelection? {
        guard let selectionData, let stored = try? SessionCapsSelection.decode(selectionData, currentBoot: boot) else { return nil }
        return stored.rebound(among: devices, currentBoot: boot)
    }

    /// Only discovers a selection. Mapping writes remain owned by the worker lease.
    /// A withheld keyboard (one KeyPath cannot target) still counts: the user
    /// may type on it, so the lone eligible one is not picked on their behalf.
    static func automaticSelection(devices: [Policy.DeviceIdentity], withheld: Int, boot: String) throws -> SessionCapsSelection {
        guard devices.count == 1, withheld == 0 else { throw Refusal.selection }
        let selection = SessionCapsSelection(device: devices[0], bootSessionUUID: boot)
        _ = try selection.approvedDevice(currentBoot: boot)
        return selection
    }

    static func startupFailureMessage(_ result: KanataHostBridgeValidationResult) -> String? {
        switch result {
        case .valid: nil
        case let .invalid(reason):
            "This configuration cannot run in driverless mode: \(reason). Edit the configuration and retry; existing rules were preserved."
        case let .unavailable(reason):
            "Driverless configuration validation is unavailable: \(reason). Retry once validation is available; existing rules were preserved."
        }
    }

    static func journalDirectory(configPath: String = KeyPathConstants.Config.mainConfigPath) -> URL {
        URL(fileURLWithPath: configPath).deletingLastPathComponent().appendingPathComponent(".session-caps-mapping", isDirectory: true)
    }

    static func bootSessionUUID() throws -> String {
        var bytes = [CChar](repeating: 0, count: 128)
        var length = bytes.count
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &length, nil, 0) == 0,
              length > 1, length <= bytes.count else { throw Refusal.bootIdentity }
        let value = String(decoding: bytes.prefix(length - 1).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        guard UUID(uuidString: value) != nil else { throw Refusal.bootIdentity }
        return value
    }

    /// Combined session state is conservative: all representable keys must be up
    /// excluding Caps Lock’s persistent latch. It does not attribute a key to a device.
    static func requirePhysicalAllUp() throws {
        guard SessionKeyMap.keyCodeToUsage.keys.filter({ $0 != 57 }).allSatisfy({ !CGEventSource.keyState(.combinedSessionState, key: $0) })
        else { throw Refusal.physicalKeysHeld }
    }

    static func configSHA256(_ path: String) throws -> String {
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Refusal.configIdentity }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var before = stat(), after = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_size > 0, before.st_size <= 65536,
              let data = try file.read(upToCount: 65537), data.count == before.st_size,
              fstat(descriptor, &after) == 0, before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw Refusal.configIdentity }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func validatedConfigDigest(_ path: String, beforeValidation: String?) throws -> String {
        guard let beforeValidation, try configSHA256(path) == beforeValidation else { throw Refusal.configIdentity }
        return beforeValidation
    }

    static func verifyActive(directory: URL, owner: Policy.Owner,
                             backend: SessionCapsMappingLease.Backend = SessionCapsHIDUtilTransport.backend(),
                             bootSessionUUID boot: () throws -> String = bootSessionUUID) throws
    {
        let lease = SessionCapsMappingLease(directory: directory, backend: backend)
        guard let record = try lease.pendingRecord(), record.owner == owner else { throw SessionCapsMappingLease.Refusal.wrongOwner }
        // Other keyboards may be connected; the leased instance must be present
        // exactly once. The intermediate stays reserved: merged events carry no attribution.
        do { try Policy.requireUnique(record.device, among: backend.enumerate()) } catch { throw Refusal.selection }
        let snapshot = try backend.read(record.device)
        _ = try Policy.restore(record: record, current: snapshot.mappings, device: snapshot.device, bootSessionUUID: boot())
        // Every recorded companion interface must still carry exactly our
        // mapping. One that could not be read this tick is not a foreign
        // write: it is checked again next tick (the chosen interface was just
        // verified). A different mapping is foreign; restore decides the rest.
        if !record.companions.isEmpty {
            let group = try backend.readGroup(record.device)
            for companion in record.companions {
                guard let mappings = group[companion.registryEntryID] else { continue }
                guard mappings == record.applied(over: companion.original) else { throw Policy.Refusal.foreignMapping }
            }
        }
    }

    /// The worker's periodic lease check. Only a leased instance that no
    /// longer exists is a disconnect; one that is present but no longer
    /// verifies (a foreign write, a duplicate locator) is lost ownership.
    static func leaseCheckFailure(registryEntryID: UInt64, verify: () throws -> Void,
                                  registryEntryExists: (UInt64) throws -> Bool) -> String?
    {
        do { try verify(); return nil } catch {
            return (try? registryEntryExists(registryEntryID)) == false ? keyboardDisconnectedReason : ownershipLostReason
        }
    }

    /// Off-main caller constructs the transport here; only scalar ownership
    /// crosses actor boundaries. A PID reused by a live process refuses recovery.
    static func recoverPending(directory: URL, expectedOwner: Policy.Owner? = nil) throws {
        var metadata = stat()
        if lstat(directory.appendingPathComponent("caps-mapping-intent.json").path, &metadata) != 0 {
            guard errno == ENOENT else { throw SessionCapsMappingLease.Refusal.unsafeFile }
            // An orphan marker has no validated boot identity. Retain it.
            if lstat(directory.appendingPathComponent("caps-mapping-mutation-in-flight.json").path, &metadata) == 0 {
                throw SessionCapsMappingLease.Refusal.mutationUncertain
            }
            guard errno == ENOENT else { throw SessionCapsMappingLease.Refusal.unsafeFile }
            return
        }
        let lease = SessionCapsMappingLease(directory: directory, backend: SessionCapsHIDUtilTransport.backend())
        let currentBoot = try bootSessionUUID()
        if try lease.retirePreviousBoot(bootSessionUUID: currentBoot) { return }
        guard let record = try lease.pendingRecord() else { return }
        if let expectedOwner {
            guard record.owner == expectedOwner else { throw SessionCapsMappingLease.Refusal.wrongOwner }
        } else {
            guard !SystemStateProvider.isProcessAlive(pid: record.owner.parentPID),
                  !SystemStateProvider.isProcessAlive(pid: record.owner.workerPID)
            else { throw Refusal.liveOwner }
        }
        try lease.restore(expectedOwner: record.owner, bootSessionUUID: currentBoot)
    }
}
