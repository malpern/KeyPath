import CryptoKit
import Darwin
import Foundation

/// FIFO admission within one service, plus a process-safe lease for its config
/// directory. Owns no persistence/UI state; trusted nested work uses a permit.
actor ConfigurationOperationGate {
    struct Permit: Sendable {
        fileprivate let owner: UUID
        fileprivate let operation: UUID
    }

    enum Failure: LocalizedError {
        case recursiveOperation
        case invalidPermit
        case fileLock(String, Int32)
        case invalidLockFile

        var errorDescription: String? {
            switch self {
            case .recursiveOperation:
                "An operation callback cannot recursively save or restore through the same configuration service."
            case .invalidPermit:
                "The configuration operation permit is no longer active."
            case let .fileLock(operation, code):
                "Configuration operation lock \(operation) failed (errno \(code))."
            case .invalidLockFile:
                "The configuration operation lock is not a regular file."
            }
        }
    }

    @TaskLocal private static var activeOperations: Set<UUID> = []
    @TaskLocal private static var fileLeases: [FileLease] = []
    private let configurationDirectory: URL?
    private let owner = UUID()
    private var active: Permit?
    private var waiters: [CheckedContinuation<Permit, Never>] = []

    init(configurationDirectory: URL? = nil) {
        self.configurationDirectory = configurationDirectory
    }

    /// Keep locks in user-owned state, not a possibly read-only config parent.
    /// Never unlink at operation end; waiters must keep one inode even on restore.
    nonisolated static func lockFileURL(for directory: URL) -> URL {
        let canonical = directory.standardizedFileURL.resolvingSymlinksInPath()
        var ancestor = canonical
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            ancestor = ancestor.deletingLastPathComponent()
        }
        let caseSensitive = try? ancestor.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames
        var path = canonical.path.precomposedStringWithCanonicalMapping
        if caseSensitive == false { path = path.lowercased() }
        let key = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/KeyPath/ConfigurationLocks", isDirectory: true)
            .appendingPathComponent("\(key).lock")
    }

    func withOperation<Result: Sendable>(
        using permit: Permit? = nil,
        _ operation: @Sendable (Permit) async throws -> Result
    ) async throws -> Result {
        if let permit {
            guard permit.owner == owner, permit.operation == active?.operation else {
                throw Failure.invalidPermit
            }
            return try await operation(permit)
        }
        try Task.checkCancellation()
        if let active, Self.activeOperations.contains(active.operation) {
            throw Failure.recursiveOperation
        }
        // Check inherited directory ownership before joining this service's queue:
        // its current operation may itself be waiting for the callback owner's lease.
        let lease: FileLease? = if let configurationDirectory {
            try await FileLease.open(directory: configurationDirectory)
        } else {
            nil
        }
        defer { lease?.release() }
        if let lease {
            // File identity also catches case and symlink aliases across service instances.
            guard !Self.fileLeases.contains(where: { $0.identity == lease.identity && $0.isActive }) else {
                throw Failure.recursiveOperation
            }
        }
        let admitted = await acquire()
        defer {
            lease?.release()
            release()
        }
        // Cancelled waiters retain their FIFO place, then leave without mutation.
        try Task.checkCancellation()
        try await lease?.acquire()
        try Task.checkCancellation()
        var context = Self.activeOperations
        context.insert(admitted.operation)
        let leases = Self.fileLeases + (lease.map { [$0] } ?? [])
        return try await Self.$activeOperations.withValue(context) {
            try await Self.$fileLeases.withValue(leases) {
                try await operation(admitted)
            }
        }
    }

    private func acquire() async -> Permit {
        if active != nil {
            return await withCheckedContinuation { waiters.append($0) }
        }
        let permit = Permit(owner: owner, operation: UUID())
        active = permit
        return permit
    }

    private func release() {
        guard !waiters.isEmpty else {
            active = nil
            return
        }
        let next = Permit(owner: owner, operation: UUID())
        active = next
        waiters.removeFirst().resume(returning: next)
    }

    private final nonisolated class FileLease: @unchecked Sendable {
        struct Identity: Equatable, Sendable {
            let device: dev_t
            let inode: ino_t
        }

        let identity: Identity
        private let stateLock = NSLock()
        private var descriptor: Int32?

        private init(descriptor: Int32, identity: Identity) {
            self.descriptor = descriptor
            self.identity = identity
        }

        var isActive: Bool {
            stateLock.withLock { descriptor != nil }
        }

        private static let ioQueue = DispatchQueue(label: "com.keypath.configuration-operation-lock", qos: .utility, attributes: .concurrent)

        static func open(directory: URL) async throws -> FileLease {
            try await withCheckedThrowingContinuation { continuation in
                ioQueue.async {
                    do {
                        try continuation.resume(returning: openFile(directory: directory))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        private static func openFile(directory: URL) throws -> FileLease {
            let url = ConfigurationOperationGate.lockFileURL(for: directory)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let fd = Darwin.open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { throw Failure.fileLock("open", errno) }
            do {
                var info = stat()
                guard fstat(fd, &info) == 0 else { throw Failure.fileLock("stat", errno) }
                guard info.st_mode & S_IFMT == S_IFREG else { throw Failure.invalidLockFile }
                return FileLease(descriptor: fd, identity: Identity(device: info.st_dev, inode: info.st_ino))
            } catch {
                Darwin.close(fd)
                throw error
            }
        }

        func acquire() async throws {
            guard let fd = stateLock.withLock({ descriptor }) else { throw Failure.invalidPermit }
            while true {
                try Task.checkCancellation()
                if flock(fd, LOCK_EX | LOCK_NB) == 0 { return }
                let code = errno
                if code == EINTR { continue }
                guard code == EWOULDBLOCK || code == EAGAIN else { throw Failure.fileLock("acquire", code) }
                // Never block the main actor or a serial file-I/O queue while waiting.
                try await Task.sleep(for: .milliseconds(50))
            }
        }

        func release() {
            let fd = stateLock.withLock {
                let previous = descriptor
                descriptor = nil
                return previous
            }
            guard let fd else { return }
            flock(fd, LOCK_UN)
            Darwin.close(fd)
        }

        deinit { release() }
    }
}
