import Carbon
import CryptoKit
import Darwin
import Foundation
import KeyPathCore

/// Caps consent and recovery shared by the existing lifecycle and worker.
/// Session events cannot distinguish another keyboard's native F18: the explicit
/// reservation is an eligibility declaration, never a device-attribution claim.
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

    static let selectionKey = "keypath.session.caps.selection.v1"
    static let selectionEnvironmentKey = "KEYPATH_SESSION_CAPS_SELECTION"

    static func selectedDevice(environment: [String: String] = ProcessInfo.processInfo.environment,
                               selectionData: Data? = UserDefaults.standard.data(forKey: selectionKey)) throws -> Policy.DeviceIdentity? {
        #if DEBUG
            if environment["KEYPATH_EXPERIMENTAL_MANAGED_CAPS_DEVICE"] != nil {
                return try experimentalDevice(environment: environment)
            }
        #endif
        let data = environment[selectionEnvironmentKey].map { Data($0.utf8) } ?? selectionData
        guard let data else { return nil }
        return try SessionCapsSelection.decode(data, currentBoot: bootSessionUUID()).device
    }

    static func validate(configPath: String, runtimeHost: KanataRuntimeHost,
                         environment: [String: String] = ProcessInfo.processInfo.environment,
                         selectionData: Data? = UserDefaults.standard.data(forKey: selectionKey)) -> (result: KanataHostBridgeValidationResult, managedCaps: Bool)
    {
        let usages = SessionKeyMap.keyCodeToUsage.values.filter { $0 != 57 }.sorted()
        let legacy = KanataHostBridge.validateSessionConfig(runtimeHost: runtimeHost, configPath: configPath, supportedUsages: usages)
        if case .valid = legacy { return (legacy, false) }
        // Parse eligibility before consent so stale setup cannot disguise an
        // unrelated syntax or unsupported-action error. This acquires no mapping.
        let managed = KanataHostBridge.validateSessionConfig(runtimeHost: runtimeHost, configPath: configPath,
                                                             supportedUsages: usages, managedCaps: true)
        guard case .valid = managed else { return (legacy, false) }
        do {
            guard try selectedDevice(environment: environment, selectionData: selectionData) != nil else { throw Refusal.selection }
            return (managed, true)
        } catch {
            return (.invalid(reason: "Caps Lock setup needs a current keyboard selection with F18 reserved. Open Settings > General to select your keyboard"), false)
        }
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
    /// and the system Caps latch off. It does not attribute a key to a device.
    static func requirePhysicalAllUp() throws {
        guard !CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift),
              SessionKeyMap.keyCodeToUsage.keys.allSatisfy({ !CGEventSource.keyState(.combinedSessionState, key: $0) })
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

    static func verifyActive(directory: URL, owner: Policy.Owner) throws {
        let backend = SessionCapsHIDUtilTransport.backend()
        let lease = SessionCapsMappingLease(directory: directory, backend: backend)
        guard let record = try lease.pendingRecord(), record.owner == owner else { throw SessionCapsMappingLease.Refusal.wrongOwner }
        // The initial prototype permits one physical keyboard, with F18
        // explicitly reserved. Do not guess attribution from merged events.
        guard try backend.enumerate() == [record.device] else { throw Refusal.selection }
        let snapshot = try backend.read(record.device)
        _ = try Policy.restore(record: record, current: snapshot.mappings, device: snapshot.device, bootSessionUUID: bootSessionUUID())
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
