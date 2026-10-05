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
                    write: @escaping (Policy.DeviceIdentity, [Policy.Mapping]) throws -> Void) {
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
        try locked { try load($0) }
    }

    /// A durable journal is fsynced before the first HID mutation. Any thrown
    /// write/readback error leaves intent pending, even if the write took effect.
    public func acquire(owner: Policy.Owner, configSHA256: String,
                        device: Policy.DeviceIdentity) throws -> Policy.Record {
        try locked { fd in
            guard try load(fd) == nil else { throw Refusal.pendingIntent }
            guard owner.uid == getuid() else { throw Refusal.wrongOwner }
            let devices = try backend.enumerate()
            let snapshot = try backend.read(device)
            guard snapshot.device == device else { throw Policy.Refusal.differentDevice }
            let record = try Policy.acquire(original: snapshot.mappings, device: device, devices: devices,
                                            owner: owner, effectiveConfigSHA256: configSHA256)
            try persist(record, directoryFD: fd)
            // Recheck the selected service immediately before mutation. Never
            // clear a journal on an unconfirmed mutation or a failed readback.
            try verifyInstance(record)
            let beforeWrite = try backend.read(device)
            guard beforeWrite.device == device else { throw Policy.Refusal.differentDevice }
            guard beforeWrite.mappings == record.original else { throw Policy.Refusal.foreignMapping }
            try backend.write(device, record.applied)
            let applied = try backend.read(device)
            guard applied.device == device, applied.mappings == record.applied else { throw Refusal.unverifiedWrite }
            return record
        }
    }

    /// Exact owner is mandatory even for recovery; inspect intent first, prove
    /// that owner dead externally, then pass the recorded owner here.
    public func restore(expectedOwner: Policy.Owner, bootSessionUUID: String) throws {
        try locked { fd in
            guard let record = try load(fd) else { return }
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
                try backend.write(record.device, original)
                let restored = try backend.read(record.device)
                guard restored.device == record.device, restored.mappings == original else { throw Refusal.unverifiedWrite }
            }
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

    private func load(_ dir: Int32) throws -> Policy.Record? {
        let fd = openat(dir, journal, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw Refusal.unsafeFile
        }
        defer { close(fd) }
        try checkFile(fd)
        var bytes = [UInt8](repeating: 0, count: maximumSize + 1)
        var count = 0
        while count < bytes.count {
            let n = bytes.withUnsafeMutableBytes { read(fd, $0.baseAddress!.advanced(by: count), $0.count - count) }
            if n < 0 { if errno == EINTR { continue }; throw Refusal.journalIO }
            if n == 0 { break }
            count += n
        }
        guard count > 0, count <= maximumSize else { throw Refusal.unsafeFile }
        return try JSONDecoder().decode(Policy.Record.self, from: Data(bytes.prefix(count)))
    }

    private func persist(_ record: Policy.Record, directoryFD: Int32) throws {
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
    }
}
