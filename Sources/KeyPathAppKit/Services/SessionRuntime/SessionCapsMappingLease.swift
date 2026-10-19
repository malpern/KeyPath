import Darwin
import Foundation
import KeyPathCore

/// One durable intent shared by the parent and worker. Call off the main actor.
/// Recovery callers must independently prove the recorded processes are dead.
/// hidutil has no compare-and-set: read/write races and identical foreign ABA
/// replacements remain unsolved; this lease does not claim atomic HID ownership.
public final class SessionCapsMappingLease {
    public typealias Policy = SessionCapsMappingPolicy
    public struct Snapshot {
        public let device: Policy.DeviceIdentity
        public let mappings: [Policy.Mapping]
        public init(device: Policy.DeviceIdentity, mappings: [Policy.Mapping]) {
            self.device = device
            self.mappings = mappings
        }
    }

    public struct Backend {
        public let enumerate: () throws -> [Policy.DeviceIdentity]
        /// Exact, unfiltered registry lookup. An unavailable lookup must throw;
        /// the default retains evidence for backends without this capability.
        public let registryEntryExists: (UInt64) throws -> Bool
        public let read: (Policy.DeviceIdentity) throws -> Snapshot
        /// Must join all mutation child processes before returning or throwing.
        /// The durable in-flight marker can be cleared only after that guarantee.
        public let write: (Policy.DeviceIdentity, [Policy.Mapping]) throws -> Void
        /// The keyboard's services the lease covers, the chosen one included.
        /// A board can deliver its keys on several interfaces (QMK's NKRO
        /// interface is mouse-primary); each one that can emit keyboard usages
        /// is a member. The default covers the chosen service only.
        public let members: (Policy.DeviceIdentity) throws -> Set<UInt64>
        /// Mappings of the keyboard's services by registry ID; covers at least
        /// `members`. Restore and verification look up recorded companions here.
        public let readGroup: (Policy.DeviceIdentity) throws -> [UInt64: [Policy.Mapping]]
        /// Writes each service its own target and verifies readback. Same
        /// joining guarantee as `write`; refuses rather than touch an unlisted service.
        public let writeEach: (Policy.DeviceIdentity, [UInt64: [Policy.Mapping]]) throws -> Void
        public init(enumerate: @escaping () throws -> [Policy.DeviceIdentity],
                    read: @escaping (Policy.DeviceIdentity) throws -> Snapshot,
                    write: @escaping (Policy.DeviceIdentity, [Policy.Mapping]) throws -> Void,
                    registryEntryExists: @escaping (UInt64) throws -> Bool = { _ in true },
                    members: ((Policy.DeviceIdentity) throws -> Set<UInt64>)? = nil,
                    readGroup: ((Policy.DeviceIdentity) throws -> [UInt64: [Policy.Mapping]])? = nil,
                    writeEach: ((Policy.DeviceIdentity, [UInt64: [Policy.Mapping]]) throws -> Void)? = nil)
        {
            self.enumerate = enumerate
            self.registryEntryExists = registryEntryExists
            self.read = read
            self.write = write
            self.members = members ?? { [$0.registryEntryID] }
            self.readGroup = readGroup ?? { try [$0.registryEntryID: read($0).mappings] }
            self.writeEach = writeEach ?? { device, targets in
                guard Set(targets.keys) == [device.registryEntryID], let mappings = targets[device.registryEntryID] else {
                    throw Policy.Refusal.differentDevice
                }
                try write(device, mappings)
            }
        }
    }

    public enum Refusal: Error, Equatable {
        case unsafeDirectory, unsafeFile, busy, pendingIntent, wrongOwner, unverifiedWrite, journalIO, mutationUncertain, invalidBootIdentity
    }

    private let directory: URL
    private let backend: Backend
    private let journal = "caps-mapping-intent.json"
    private let mutationMarker = "caps-mapping-mutation-in-flight.json"
    private let maximumSize = 65536

    public init(directory: URL, backend: Backend) {
        self.directory = directory
        self.backend = backend
    }

    public func pendingRecord() throws -> Policy.Record? {
        try locked { try load($0)?.record }
    }

    /// Excludes every lease mutation until the caller confirms worker exit.
    /// Hold through signal delivery AND exit observation, including a timed-out
    /// wait. Absence of a journal/directory does not bypass this exclusion.
    func acquireTerminationGuard(expectedOwner: Policy.Owner) throws -> TerminationGuard {
        let guardHandle = try acquireLock()
        do {
            try requireNoMutation(directoryFD: guardHandle.directoryFD)
            guard expectedOwner.uid == getuid() else { throw Refusal.wrongOwner }
            if let entry = try load(guardHandle.directoryFD) {
                guard entry.record.owner == expectedOwner else { throw Refusal.wrongOwner }
            }
            return guardHandle
        } catch {
            guardHandle.release()
            throw error
        }
    }

    /// Descriptor ownership may cross from a background acquisition to lifecycle
    /// cleanup. Release is synchronized and idempotent; it performs no HID work.
    final class TerminationGuard: @unchecked Sendable {
        fileprivate let directoryFD: Int32
        private let lockFD: Int32
        private let releaseLock = NSLock()
        private var released = false

        fileprivate init(directoryFD: Int32, lockFD: Int32) {
            self.directoryFD = directoryFD
            self.lockFD = lockFD
        }

        func release() {
            releaseLock.lock()
            defer { releaseLock.unlock() }
            guard !released else { return }
            released = true
            flock(lockFD, LOCK_UN)
            close(lockFD)
            close(directoryFD)
        }

        deinit { release() }
    }

    /// A verified reboot ends every old writer and invalidates its registry ID.
    /// Retire owned previous-boot evidence only; never restore or inspect HID here.
    /// Marker first, then intent, so interrupted retirement remains retryable.
    @discardableResult
    public func retirePreviousBoot(bootSessionUUID: String) throws -> Bool {
        guard let currentBoot = UUID(uuidString: bootSessionUUID) else { throw Refusal.invalidBootIdentity }
        return try locked { fd in
            guard let loaded = try load(fd) else {
                try requireNoMutation(directoryFD: fd)
                return false
            }
            guard loaded.record.owner.uid == getuid() else { throw Refusal.wrongOwner }
            guard UUID(uuidString: loaded.record.owner.bootSessionUUID) != currentBoot else {
                try requireNoMutation(directoryFD: fd)
                return false
            }
            if let marker = try loadFile(mutationMarker, directoryFD: fd) {
                let ownerKeys: Set = ["uid", "parentPID", "workerPID", "nonce", "generation", "bootSessionUUID"]
                guard let object = try JSONSerialization.jsonObject(with: marker.data) as? [String: Any],
                      Set(object.keys) == ownerKeys else { throw Refusal.unsafeFile }
                let owner = try JSONDecoder().decode(Policy.Owner.self, from: marker.data)
                guard owner == loaded.record.owner else { throw Refusal.wrongOwner }
                try verifyJournal(loaded, directoryFD: fd)
                try clearMarker(marker.metadata, directoryFD: fd)
            }
            try requireNoMutation(directoryFD: fd)
            try verifyJournal(loaded, directoryFD: fd)
            guard unlinkat(fd, journal, 0) == 0, fsync(fd) == 0 else { throw Refusal.journalIO }
            return true
        }
    }

    /// A durable journal is fsynced before the first HID mutation. Any thrown
    /// write/readback error leaves intent pending, even if the write took effect.
    public func acquire(owner: Policy.Owner, configSHA256: String, device: Policy.DeviceIdentity,
                        intermediate: UInt64 = Policy.f18) throws -> Policy.Record
    {
        try locked { fd in
            try requireNoMutation(directoryFD: fd)
            guard try load(fd) == nil else { throw Refusal.pendingIntent }
            guard owner.uid == getuid() else { throw Refusal.wrongOwner }
            let devices = try backend.enumerate()
            let snapshot = try backend.read(device)
            guard snapshot.device == device else { throw Policy.Refusal.differentDevice }
            let companions = try companionMappings(device)
            let record = try Policy.acquire(original: snapshot.mappings, device: device, devices: devices,
                                            owner: owner, effectiveConfigSHA256: configSHA256,
                                            intermediate: intermediate, companions: companions)
            let persisted = try persist(record, directoryFD: fd)
            // Recheck the selected service immediately before mutation. Never
            // clear a journal on an unconfirmed mutation or a failed readback.
            do {
                try verifyInstance(record)
                let beforeWrite = try backend.read(device)
                guard beforeWrite.device == device else { throw Policy.Refusal.differentDevice }
                guard beforeWrite.mappings == record.original else { throw Policy.Refusal.foreignMapping }
                // Look the recorded companions up again rather than re-probing
                // which interfaces exist: a probe that flips is not a foreign write.
                if !companions.isEmpty {
                    let group = try backend.readGroup(device)
                    guard companions.allSatisfy({ group[$0.key] == $0.value }) else { throw Policy.Refusal.foreignMapping }
                }
            } catch {
                // Refused before any write: no mutation marker exists, so nothing
                // was applied and the intent is void. Left on disk, restore() would
                // find current ≠ original ≠ applied and refuse every later stop.
                if (try? requireNoMutation(directoryFD: fd)) != nil,
                   (try? verifyJournal(persisted, directoryFD: fd)) != nil,
                   unlinkat(fd, journal, 0) == 0
                {
                    _ = fsync(fd)
                }
                throw error
            }
            try verifyJournal(persisted, directoryFD: fd)
            var targets: [UInt64: [Policy.Mapping]] = [:]
            for service in record.originals {
                targets[service.registryEntryID] = record.applied(over: service.original)
            }
            try mutate(record: record, targets: targets, directoryFD: fd, initialApply: true)
            let applied = try backend.read(device)
            guard applied.device == device, applied.mappings == record.applied else { throw Refusal.unverifiedWrite }
            if !record.companions.isEmpty {
                let now = try backend.readGroup(device)
                guard targets.allSatisfy({ now[$0.key] == $0.value }) else { throw Refusal.unverifiedWrite }
            }
            try requireNoMutation(directoryFD: fd)
            try verifyJournal(persisted, directoryFD: fd)
            return record
        }
    }

    /// Exact owner is mandatory even for recovery; inspect intent first, prove
    /// that owner dead externally, then pass the recorded owner here.
    public func restore(expectedOwner: Policy.Owner, bootSessionUUID: String) throws {
        try locked { fd in
            try requireNoMutation(directoryFD: fd)
            guard let loaded = try load(fd) else { return }
            let record = loaded.record
            guard record.owner == expectedOwner, record.owner.uid == getuid() else { throw Refusal.wrongOwner }
            guard bootSessionUUID == record.owner.bootSessionUUID else { throw Policy.Refusal.differentBoot }
            // IORegistry IDs identify one service for this boot. Once that exact
            // service is gone, its property is gone too. Retire only its intent;
            // a replacement with the same serial/location is never a restore target.
            // requireNoMutation above remains mandatory: a queued selector-based
            // hidutil child could otherwise write to the replacement later.
            if try !backend.registryEntryExists(record.device.registryEntryID) {
                try requireNoMutation(directoryFD: fd)
                try verifyJournal(loaded, directoryFD: fd)
                guard unlinkat(fd, journal, 0) == 0, fsync(fd) == 0 else { throw Refusal.journalIO }
                return
            }
            try verifyInstance(record)
            let snapshot = try backend.read(record.device)
            guard snapshot.device == record.device else { throw Policy.Refusal.differentDevice }
            // Every recorded interface must hold its original or exactly what we
            // applied there; a write that failed part-way leaves some of each.
            // A recorded companion that still exists but cannot be read refuses:
            // the covered set never shrinks, so no interface keeps our mapping
            // after the intent is gone. Anything else is foreign.
            var current = [record.device.registryEntryID: snapshot.mappings]
            if !record.companions.isEmpty {
                let group = try backend.readGroup(record.device)
                for companion in record.companions {
                    if let mappings = group[companion.registryEntryID] {
                        current[companion.registryEntryID] = mappings
                    } else if try backend.registryEntryExists(companion.registryEntryID) {
                        throw Policy.Refusal.differentDevice
                    }
                }
            }
            var targets: [UInt64: [Policy.Mapping]] = [:]
            for (id, mappings) in current {
                targets[id] = id == record.device.registryEntryID && mappings != record.original
                    ? try Policy.restore(record: record, current: mappings, device: snapshot.device, bootSessionUUID: bootSessionUUID)
                    : try Policy.restoreService(record: record, registryEntryID: id, current: mappings, bootSessionUUID: bootSessionUUID)
            }
            // Explicit verification also resolves intent after a write that
            // failed before changing anything, or a crash after restoration.
            if targets.contains(where: { current[$0.key] != $0.value }) {
                try verifyJournal(loaded, directoryFD: fd)
                try mutate(record: record, targets: targets, directoryFD: fd, initialApply: false)
                let restored = try backend.read(record.device)
                guard restored.device == record.device, restored.mappings == record.original else { throw Refusal.unverifiedWrite }
                if targets.count > 1 {
                    let group = try backend.readGroup(record.device)
                    guard targets.allSatisfy({ group[$0.key] == $0.value }) else { throw Refusal.unverifiedWrite }
                }
            }
            try requireNoMutation(directoryFD: fd)
            try verifyJournal(loaded, directoryFD: fd)
            guard unlinkat(fd, journal, 0) == 0, fsync(fd) == 0 else { throw Refusal.journalIO }
        }
    }

    /// A marker surviving worker death may mean an orphan hidutil still owns a
    /// pending write. Never infer safety from owner PIDs, elapsed time, or maps
    /// currently reading original: a late child write can follow that read.
    private func requireNoMutation(directoryFD: Int32) throws {
        var metadata = stat()
        if fstatat(directoryFD, mutationMarker, &metadata, AT_SYMLINK_NOFOLLOW) == 0 {
            throw Refusal.mutationUncertain
        }
        guard errno == ENOENT else { throw Refusal.mutationUncertain }
    }

    private func mutate(record: Policy.Record, targets: [UInt64: [Policy.Mapping]], directoryFD: Int32, initialApply: Bool) throws {
        // The chosen service's target; the DEBUG checkpoints are defined on it.
        let mappings = targets[record.device.registryEntryID] ?? []
        let data = try JSONEncoder().encode(record.owner)
        let fd = openat(directoryFD, mutationMarker, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Refusal.mutationUncertain }
        defer { close(fd) }
        try checkFile(fd)
        var written = 0
        try data.withUnsafeBytes { bytes in
            while written < bytes.count {
                let n = write(fd, bytes.baseAddress!.advanced(by: written), bytes.count - written)
                if n < 0 { if errno == EINTR { continue }; throw Refusal.mutationUncertain }
                guard n > 0 else { throw Refusal.mutationUncertain }
                written += n
            }
        }
        guard fsync(fd) == 0, fsync(directoryFD) == 0 else { throw Refusal.mutationUncertain }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0 else { throw Refusal.mutationUncertain }
        // Verify the entry before launching a child as well as before removal.
        try verifyMarker(metadata, directoryFD: directoryFD)
        #if DEBUG
            if Self.terminateWithQueuedWriter(record: record, mappings: mappings, initialApply: initialApply) {
                // Outside the joined-backend catch: uncertainty must survive any experiment failure.
                try SessionCapsHIDUtilTransport.terminateOwnerWithSuspendedWriter(record: record, mappings: mappings) { childPID in
                    let proof = try JSONSerialization.data(withJSONObject: [
                        "phase": "queued-writer-before-execution", "childPID": childPID,
                        "owner": JSONSerialization.jsonObject(with: JSONEncoder().encode(record.owner)),
                        "device": JSONSerialization.jsonObject(with: JSONEncoder().encode(record.device))
                    ], options: [.sortedKeys])
                    guard proof.count <= 4096 else { throw Refusal.mutationUncertain }
                    let checkpoint = openat(directoryFD, "caps-mapping-queued-writer-checkpoint.json",
                                            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
                    guard checkpoint >= 0 else { throw Refusal.mutationUncertain }
                    defer { close(checkpoint) }
                    try checkFile(checkpoint)
                    try proof.withUnsafeBytes { bytes in
                        var offset = 0
                        while offset < bytes.count {
                            let count = Darwin.write(checkpoint, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                            if count < 0, errno == EINTR { continue }
                            guard count > 0 else { throw Refusal.mutationUncertain }
                            offset += count
                        }
                    }
                    guard fsync(checkpoint) == 0, fsync(directoryFD) == 0 else { throw Refusal.mutationUncertain }
                    try verifyMarker(metadata, directoryFD: directoryFD)
                }
            }
        #endif
        do {
            try backend.writeEach(record.device, targets)
        } catch {
            try clearMarker(metadata, directoryFD: directoryFD)
            throw error
        }
        #if DEBUG
            if Self.terminateAfterJoinedApply(record: record, mappings: mappings) {
                let line = "Caps checkpoint phase=after-joined-write nonce=\(record.owner.nonce) generation=\(record.owner.generation) registry=\(record.device.registryEntryID)\n"
                FileHandle.standardError.write(Data(line.utf8))
                Darwin.kill(getpid(), SIGKILL)
                throw Refusal.mutationUncertain // Never clear intent if termination unexpectedly returns.
            }
        #endif
        try clearMarker(metadata, directoryFD: directoryFD)
    }

    #if DEBUG
        static func terminateWithQueuedWriter(record: Policy.Record, mappings: [Policy.Mapping],
                                              initialApply: Bool = true,
                                              environment: [String: String] = ProcessInfo.processInfo.environment,
                                              uid: UInt32 = getuid(), pid: Int32 = getpid()) -> Bool
        {
            guard initialApply, let selected = environment["KEYPATH_EXPERIMENTAL_CAPS_TERMINATE_WITH_QUEUED_WRITER"] else { return false }
            var admission = environment
            admission["KEYPATH_EXPERIMENTAL_CAPS_TERMINATE_AFTER_JOINED_APPLY"] = selected
            return terminateAfterJoinedApply(record: record, mappings: mappings, environment: admission, uid: uid, pid: pid)
        }

        /// Inert unless a disposable worker opts into its exact selected registry.
        /// Called only after successful joined write, while the owner marker is durable.
        static func terminateAfterJoinedApply(record: Policy.Record, mappings: [Policy.Mapping],
                                              environment: [String: String] = ProcessInfo.processInfo.environment,
                                              uid: UInt32 = getuid(), pid: Int32 = getpid()) -> Bool
        {
            guard uid == 502, record.owner.uid == uid, pid == record.owner.workerPID,
                  pid != record.owner.parentPID, mappings == record.applied,
                  record.device.vendorID == 51966, record.device.productID == 16400,
                  environment["KEYPATH_EXPERIMENTAL_CAPS_TERMINATE_AFTER_JOINED_APPLY"] == String(record.device.registryEntryID),
                  environment["KEYPATH_EXPERIMENTAL_MANAGED_CAPS_RESERVE_F18"] == "1",
                  let raw = environment["KEYPATH_EXPERIMENTAL_MANAGED_CAPS_DEVICE"], raw.utf8.count <= 4096,
                  let selected = try? JSONDecoder().decode(Policy.DeviceIdentity.self, from: Data(raw.utf8)),
                  selected == record.device else { return false }
            return true
        }
    #endif

    private func verifyMarker(_ expected: stat, directoryFD: Int32) throws {
        var current = stat()
        guard fstatat(directoryFD, mutationMarker, &current, AT_SYMLINK_NOFOLLOW) == 0,
              sameEntry(expected, current) else { throw Refusal.mutationUncertain }
    }

    private func clearMarker(_ expected: stat, directoryFD: Int32) throws {
        try verifyMarker(expected, directoryFD: directoryFD)
        guard unlinkat(directoryFD, mutationMarker, 0) == 0, fsync(directoryFD) == 0 else { throw Refusal.mutationUncertain }
    }

    /// Current mappings of the chosen keyboard's other covered interfaces.
    private func companionMappings(_ device: Policy.DeviceIdentity) throws -> [UInt64: [Policy.Mapping]] {
        let members = try backend.members(device)
        guard members.contains(device.registryEntryID) else { throw Policy.Refusal.differentDevice }
        guard members.count > 1 else { return [:] }
        let group = try backend.readGroup(device)
        var result: [UInt64: [Policy.Mapping]] = [:]
        for id in members where id != device.registryEntryID {
            guard let mappings = group[id] else { throw Policy.Refusal.differentDevice }
            result[id] = mappings
        }
        return result
    }

    private func verifyInstance(_ record: Policy.Record) throws {
        // Reuse policy's exact registry and selector uniqueness checks without
        // losing or normalizing any original mapping rows.
        _ = try Policy.acquire(original: record.original, device: record.device, devices: backend.enumerate(),
                               owner: record.owner, effectiveConfigSHA256: record.effectiveConfigSHA256,
                               intermediate: record.intermediate)
    }

    private func locked<T>(_ body: (Int32) throws -> T) throws -> T {
        let guardHandle = try acquireLock()
        defer { guardHandle.release() }
        return try body(guardHandle.directoryFD)
    }

    private func acquireLock() throws -> TerminationGuard {
        if mkdir(directory.path, 0o700) != 0, errno != EEXIST { throw Refusal.unsafeDirectory }
        let dir = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dir >= 0 else { throw Refusal.unsafeDirectory }
        var transferred = false
        defer { if !transferred { close(dir) } }
        var info = stat()
        guard fstat(dir, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o7777 == 0o700 else {
            throw Refusal.unsafeDirectory
        }
        let lock = openat(dir, "caps-mapping.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw Refusal.unsafeFile }
        defer { if !transferred { close(lock) } }
        try checkFile(lock)
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw Refusal.busy }
        transferred = true
        return TerminationGuard(directoryFD: dir, lockFD: lock)
    }

    private func checkFile(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o7777 == 0o600, info.st_nlink == 1,
              info.st_size >= 0, info.st_size <= maximumSize else { throw Refusal.unsafeFile }
    }

    private struct JournalEntry {
        let record: Policy.Record
        let metadata: stat
    }

    private func sameEntry(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && lhs.st_mode == rhs.st_mode
            && lhs.st_uid == rhs.st_uid && lhs.st_gid == rhs.st_gid && lhs.st_nlink == rhs.st_nlink
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    private func verifyJournal(_ entry: JournalEntry, directoryFD: Int32) throws {
        var current = stat()
        guard fstatat(directoryFD, journal, &current, AT_SYMLINK_NOFOLLOW) == 0,
              sameEntry(entry.metadata, current) else { throw Refusal.unsafeFile }
    }

    private func load(_ dir: Int32) throws -> JournalEntry? {
        guard let file = try loadFile(journal, directoryFD: dir) else { return nil }
        let entry = try JournalEntry(record: JSONDecoder().decode(Policy.Record.self, from: file.data), metadata: file.metadata)
        try verifyJournal(entry, directoryFD: dir)
        return entry
    }

    private func loadFile(_ name: String, directoryFD: Int32) throws -> (data: Data, metadata: stat)? {
        // A foreign FIFO must fail fstat, not block the lifecycle while opening.
        let fd = openat(directoryFD, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw Refusal.unsafeFile
        }
        defer { close(fd) }
        try checkFile(fd)
        var before = stat()
        guard fstat(fd, &before) == 0 else { throw Refusal.journalIO }
        var bytes = [UInt8](repeating: 0, count: maximumSize + 1)
        var count = 0
        while count < bytes.count {
            let n = bytes.withUnsafeMutableBytes { read(fd, $0.baseAddress!.advanced(by: count), $0.count - count) }
            if n < 0 { if errno == EINTR { continue }; throw Refusal.journalIO }
            if n == 0 { break }
            count += n
        }
        guard count > 0, count <= maximumSize else { throw Refusal.unsafeFile }
        var after = stat(), current = stat()
        guard fstat(fd, &after) == 0, sameEntry(before, after), count == before.st_size,
              fstatat(directoryFD, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
              sameEntry(before, current) else { throw Refusal.unsafeFile }
        return (Data(bytes.prefix(count)), before)
    }

    private func persist(_ record: Policy.Record, directoryFD: Int32) throws -> JournalEntry {
        let data = try JSONEncoder().encode(record)
        guard data.count <= maximumSize else { throw Refusal.unsafeFile }
        let fd = openat(directoryFD, journal, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Refusal.journalIO }
        defer { close(fd) }
        try checkFile(fd)
        var written = 0
        try data.withUnsafeBytes { bytes in
            while written < bytes.count {
                let n = write(fd, bytes.baseAddress!.advanced(by: written), bytes.count - written)
                if n < 0 { if errno == EINTR { continue }; throw Refusal.journalIO }
                guard n > 0 else { throw Refusal.journalIO }
                written += n
            }
        }
        guard fsync(fd) == 0, fsync(directoryFD) == 0 else { throw Refusal.journalIO }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0 else { throw Refusal.journalIO }
        let entry = JournalEntry(record: record, metadata: metadata)
        try verifyJournal(entry, directoryFD: directoryFD)
        return entry
    }
}
