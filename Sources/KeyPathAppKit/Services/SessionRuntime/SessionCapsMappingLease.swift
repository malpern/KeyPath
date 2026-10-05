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
        public let read: (Policy.DeviceIdentity) throws -> Snapshot
        public let write: (Policy.DeviceIdentity, [Policy.Mapping]) throws -> Void
        public init(enumerate: @escaping () throws -> [Policy.DeviceIdentity],
                    read: @escaping (Policy.DeviceIdentity) throws -> Snapshot,
                    write: @escaping (Policy.DeviceIdentity, [Policy.Mapping]) throws -> Void)
        {
            self.enumerate = enumerate
            self.read = read
            self.write = write
        }
    }

    public enum Refusal: Error, Equatable {
        case unsafeDirectory, unsafeFile, busy, pendingIntent, wrongOwner, unverifiedWrite, journalIO
    }

    private let directory: URL
    private let backend: Backend
    private let journal = "caps-mapping-intent.json"
    private let maximumSize = 65536

    public init(directory: URL, backend: Backend) {
        self.directory = directory
        self.backend = backend
    }

    public func pendingRecord() throws -> Policy.Record? {
        try locked { try load($0)?.record }
    }

    /// A durable journal is fsynced before the first HID mutation. Any thrown
    /// write/readback error leaves intent pending, even if the write took effect.
    public func acquire(owner: Policy.Owner, configSHA256: String,
                        device: Policy.DeviceIdentity) throws -> Policy.Record
    {
        try locked { fd in
            guard try load(fd) == nil else { throw Refusal.pendingIntent }
            guard owner.uid == getuid() else { throw Refusal.wrongOwner }
            let devices = try backend.enumerate()
            let snapshot = try backend.read(device)
            guard snapshot.device == device else { throw Policy.Refusal.differentDevice }
            let record = try Policy.acquire(original: snapshot.mappings, device: device, devices: devices,
                                            owner: owner, effectiveConfigSHA256: configSHA256)
            let persisted = try persist(record, directoryFD: fd)
            // Recheck the selected service immediately before mutation. Never
            // clear a journal on an unconfirmed mutation or a failed readback.
            try verifyInstance(record)
            let beforeWrite = try backend.read(device)
            guard beforeWrite.device == device else { throw Policy.Refusal.differentDevice }
            guard beforeWrite.mappings == record.original else { throw Policy.Refusal.foreignMapping }
            try verifyJournal(persisted, directoryFD: fd)
            try backend.write(device, record.applied)
            let applied = try backend.read(device)
            guard applied.device == device, applied.mappings == record.applied else { throw Refusal.unverifiedWrite }
            try verifyJournal(persisted, directoryFD: fd)
            return record
        }
    }

    /// Exact owner is mandatory even for recovery; inspect intent first, prove
    /// that owner dead externally, then pass the recorded owner here.
    public func restore(expectedOwner: Policy.Owner, bootSessionUUID: String) throws {
        try locked { fd in
            guard let loaded = try load(fd) else { return }
            let record = loaded.record
            guard record.owner == expectedOwner, record.owner.uid == getuid() else { throw Refusal.wrongOwner }
            guard bootSessionUUID == record.owner.bootSessionUUID else { throw Policy.Refusal.differentBoot }
            try verifyInstance(record)
            let snapshot = try backend.read(record.device)
            guard snapshot.device == record.device else { throw Policy.Refusal.differentDevice }
            // Explicit verification also resolves intent after a write that
            // failed before changing anything, or a crash after restoration.
            if snapshot.mappings != record.original {
                let original = try Policy.restore(record: record, current: snapshot.mappings,
                                                  device: snapshot.device, bootSessionUUID: bootSessionUUID)
                try verifyJournal(loaded, directoryFD: fd)
                try backend.write(record.device, original)
                let restored = try backend.read(record.device)
                guard restored.device == record.device, restored.mappings == original else { throw Refusal.unverifiedWrite }
            }
            try verifyJournal(loaded, directoryFD: fd)
            guard unlinkat(fd, journal, 0) == 0, fsync(fd) == 0 else { throw Refusal.journalIO }
        }
    }

    private func verifyInstance(_ record: Policy.Record) throws {
        // Reuse policy's exact registry and selector uniqueness checks without
        // losing or normalizing any original mapping rows.
        _ = try Policy.acquire(original: record.original, device: record.device, devices: backend.enumerate(),
                               owner: record.owner, effectiveConfigSHA256: record.effectiveConfigSHA256)
    }

    private func locked<T>(_ body: (Int32) throws -> T) throws -> T {
        if mkdir(directory.path, 0o700) != 0, errno != EEXIST { throw Refusal.unsafeDirectory }
        let dir = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dir >= 0 else { throw Refusal.unsafeDirectory }
        defer { close(dir) }
        var info = stat()
        guard fstat(dir, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o7777 == 0o700 else {
            throw Refusal.unsafeDirectory
        }
        let lock = openat(dir, "caps-mapping.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw Refusal.unsafeFile }
        defer { close(lock) }
        try checkFile(lock)
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw Refusal.busy }
        defer { flock(lock, LOCK_UN) }
        return try body(dir)
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
        // A foreign FIFO must fail fstat, not block the lifecycle while opening.
        let fd = openat(dir, journal, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
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
        var after = stat()
        guard fstat(fd, &after) == 0, sameEntry(before, after), count == before.st_size else { throw Refusal.unsafeFile }
        let entry = try JournalEntry(record: JSONDecoder().decode(Policy.Record.self, from: Data(bytes.prefix(count))), metadata: before)
        try verifyJournal(entry, directoryFD: dir)
        return entry
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
