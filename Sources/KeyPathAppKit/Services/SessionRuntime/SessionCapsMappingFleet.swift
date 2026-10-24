import Darwin
import Foundation
import KeyPathCore

/// Owns one existing, crash-recoverable lease per physical keyboard. The root
/// lease lock is also the parent's termination guard: no hidutil writer can be
/// launched after the parent has begun killing the worker.
struct SessionCapsMappingFleet {
    typealias Policy = SessionCapsMappingPolicy

    let directory: URL
    let backend: SessionCapsMappingLease.Backend

    private var fleetDirectory: URL {
        directory.appendingPathComponent("keyboards", isDirectory: true)
    }

    private func deviceDirectory(_ id: UInt64) -> URL {
        fleetDirectory.appendingPathComponent(String(id), isDirectory: true)
    }

    @discardableResult
    private func ensureFleetDirectory(create: Bool) throws -> Bool {
        var info = stat()
        if lstat(fleetDirectory.path, &info) != 0 {
            guard errno == ENOENT else { throw SessionCapsMappingLease.Refusal.unsafeDirectory }
            guard create else { return false }
            if mkdir(fleetDirectory.path, 0o700) != 0, errno != EEXIST {
                throw SessionCapsMappingLease.Refusal.unsafeDirectory
            }
            guard lstat(fleetDirectory.path, &info) == 0 else {
                throw SessionCapsMappingLease.Refusal.unsafeDirectory
            }
        }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(),
              info.st_mode & 0o7777 == 0o700 else { throw SessionCapsMappingLease.Refusal.unsafeDirectory }
        return true
    }

    private func withRootGuard<T>(owner: Policy.Owner, _ operation: () throws -> T) throws -> T {
        let root = SessionCapsMappingLease(directory: directory, backend: backend)
        let guardHandle = try root.acquireTerminationGuard(expectedOwner: owner)
        defer { guardHandle.release() }
        return try operation()
    }

    /// A failed device is left uncovered while working keyboards remain live.
    /// An uncertain write is restored under its exact owner before continuing.
    /// If safe restoration fails, the whole admission fails closed.
    func acquire(owner: Policy.Owner, configSHA256: String, devices: [Policy.DeviceIdentity],
                 intermediate: UInt64) throws -> (records: [Policy.Record], failures: [UInt64: String])
    {
        try withRootGuard(owner: owner) {
            try ensureFleetDirectory(create: true)
            var records: [Policy.Record] = []
            var failures: [UInt64: String] = [:]
            for device in devices {
                let lease = SessionCapsMappingLease(directory: deviceDirectory(device.registryEntryID), backend: backend)
                do {
                    let record = try lease.acquire(owner: owner, configSHA256: configSHA256,
                                                   device: device, intermediate: intermediate)
                    records.append(record)
                } catch {
                    failures[device.registryEntryID] = String(describing: error)
                    if let pending = try lease.pendingRecord() {
                        guard pending.owner == owner else { throw SessionCapsMappingLease.Refusal.wrongOwner }
                        try lease.restore(expectedOwner: owner, bootSessionUUID: owner.bootSessionUUID)
                    }
                }
            }
            return (records, failures)
        }
    }

    func pendingRecords(owner: Policy.Owner) throws -> [Policy.Record] {
        try withRootGuard(owner: owner) { try recordsOnDisk() }
    }

    /// Read-only status, never used to authorize a write. Only verified live
    /// worker records count; an old journal is not evidence of coverage.
    func activeDeviceIDs(bootSessionUUID: String,
                         processAlive: (Int32) -> Bool = SystemStateProvider.isProcessAlive) throws -> Set<UInt64>
    {
        var active = Set<UInt64>()
        for record in try recordsOnDisk() where record.owner.bootSessionUUID == bootSessionUUID
            && processAlive(record.owner.workerPID)
        {
            if (try? SessionCapsRuntimeSupport.verifyActive(
                directory: deviceDirectory(record.device.registryEntryID), owner: record.owner,
                backend: backend, bootSessionUUID: { bootSessionUUID }
            )) != nil {
                active.insert(record.device.registryEntryID)
            }
        }
        return active
    }

    /// The worker calls this off the main run loop. A removed service is
    /// retired; a newly arrived one is acquired under the same root exclusion.
    func reconcile(owner: Policy.Owner, configSHA256: String, devices: [Policy.DeviceIdentity],
                   intermediate: UInt64, bootSessionUUID: String,
                   allowNewDevices: Bool = true) throws -> (records: [Policy.Record], failures: [UInt64: String])
    {
        try withRootGuard(owner: owner) {
            var failures: [UInt64: String] = [:]
            let present = Set(devices.map(\.registryEntryID))
            for record in try recordsOnDisk() {
                guard record.owner == owner else { throw SessionCapsMappingLease.Refusal.wrongOwner }
                let lease = SessionCapsMappingLease(directory: deviceDirectory(record.device.registryEntryID), backend: backend)
                if !present.contains(record.device.registryEntryID),
                   try !backend.registryEntryExists(record.device.registryEntryID)
                {
                    try lease.restore(expectedOwner: owner, bootSessionUUID: bootSessionUUID)
                } else {
                    do {
                        try SessionCapsRuntimeSupport.verifyActive(
                            directory: deviceDirectory(record.device.registryEntryID), owner: owner, backend: backend,
                            bootSessionUUID: { bootSessionUUID }
                        )
                    } catch {
                        try lease.restore(expectedOwner: owner, bootSessionUUID: bootSessionUUID)
                        failures[record.device.registryEntryID] = String(describing: error)
                    }
                }
            }
            var records = try recordsOnDisk()
            let leased = Set(records.map(\.device.registryEntryID))
            for device in devices where allowNewDevices && !leased.contains(device.registryEntryID)
                && failures[device.registryEntryID] == nil
            {
                let lease = SessionCapsMappingLease(directory: deviceDirectory(device.registryEntryID), backend: backend)
                do {
                    try records.append(lease.acquire(owner: owner, configSHA256: configSHA256,
                                                     device: device, intermediate: intermediate))
                } catch {
                    failures[device.registryEntryID] = String(describing: error)
                    if let pending = try lease.pendingRecord() {
                        guard pending.owner == owner else { throw SessionCapsMappingLease.Refusal.wrongOwner }
                        try lease.restore(expectedOwner: owner, bootSessionUUID: bootSessionUUID)
                    }
                }
            }
            return (records, failures)
        }
    }

    /// The old single-keyboard record remains in the root directory. Fleet
    /// records are recovered independently, preserving failures for a later
    /// exact-owner retry instead of discarding working devices' recovery data.
    func recover(expectedOwner: Policy.Owner?, bootSessionUUID: String,
                 processAlive: (Int32) -> Bool = SystemStateProvider.isProcessAlive) throws
    {
        var firstFailure: Error?
        for id in try deviceIDsOnDisk() {
            let lease = SessionCapsMappingLease(directory: deviceDirectory(id), backend: backend)
            do {
                guard let record = try lease.pendingRecord() else { continue }
                guard record.device.registryEntryID == id else { throw SessionCapsMappingLease.Refusal.unsafeFile }
                let owner = record.owner
                if owner.bootSessionUUID != bootSessionUUID {
                    try lease.retirePreviousBoot(bootSessionUUID: bootSessionUUID)
                    continue
                }
                if let expectedOwner {
                    guard expectedOwner == owner else { throw SessionCapsMappingLease.Refusal.wrongOwner }
                } else {
                    guard !processAlive(owner.parentPID), !processAlive(owner.workerPID)
                    else { throw SessionCapsRuntimeSupport.Refusal.liveOwner }
                }
                try withRootGuard(owner: owner) {
                    try lease.restore(expectedOwner: owner, bootSessionUUID: bootSessionUUID)
                }
            } catch {
                if firstFailure == nil { firstFailure = error }
            }
        }
        if let firstFailure { throw firstFailure }
    }

    /// Restore every record even if one device is foreign or unreadable. The
    /// failed record remains on disk; successful records are retired.
    func restore(owner: Policy.Owner, bootSessionUUID: String) throws {
        try withRootGuard(owner: owner) {
            var firstFailure: Error?
            for id in try deviceIDsOnDisk() {
                let lease = SessionCapsMappingLease(directory: deviceDirectory(id), backend: backend)
                do {
                    guard let record = try lease.pendingRecord() else { continue }
                    guard record.device.registryEntryID == id else { throw SessionCapsMappingLease.Refusal.unsafeFile }
                    try lease.restore(expectedOwner: owner, bootSessionUUID: bootSessionUUID)
                } catch {
                    if firstFailure == nil { firstFailure = error }
                }
            }
            if let firstFailure { throw firstFailure }
        }
    }

    private func recordsOnDisk() throws -> [Policy.Record] {
        try deviceIDsOnDisk().compactMap { id in
            let lease = SessionCapsMappingLease(directory: deviceDirectory(id), backend: backend)
            guard let record = try lease.pendingRecord() else { return nil }
            guard record.device.registryEntryID == id else { throw SessionCapsMappingLease.Refusal.unsafeFile }
            return record
        }
    }

    private func deviceIDsOnDisk() throws -> [UInt64] {
        guard try ensureFleetDirectory(create: false) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: fleetDirectory.path).map { name in
            guard let id = UInt64(name), String(id) == name else { throw SessionCapsMappingLease.Refusal.unsafeDirectory }
            return id
        }.sorted()
    }
}
