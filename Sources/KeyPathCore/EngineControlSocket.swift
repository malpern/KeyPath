import Darwin
import Foundation

/// Where the session worker's engine listens for KeyPath (ADR-046).
///
/// The engine used to listen on loopback TCP, which any local process could
/// reach. It now listens on a Unix-domain socket in a 0700 directory owned by
/// this user, and the engine admits only the app that launched the worker
/// (uid, PID and PID version, checked on every accept).
///
/// Each worker names its socket after its own PID, so a worker that is still
/// shutting down can never remove the socket of the worker that replaced it.
/// The path is in the worker's report; clients read it there and never assume
/// a directory, because a long home path moves it to the fallback.
public enum EngineControlSocket {
    public enum SetupError: Error, Equatable, CustomStringConvertible {
        case pathTooLong
        case directory(String)
        case socket(String)

        public var description: String {
            switch self {
            case .pathTooLong: "engine control socket path is too long for sun_path, in both locations"
            case let .directory(reason): "engine control directory: \(reason)"
            case let .socket(reason): "engine control socket: \(reason)"
            }
        }
    }

    /// A bound, listening socket and its path. The descriptor is handed to the bridge.
    public struct Listener: Sendable, Equatable {
        public let fd: Int32
        public let path: String
    }

    /// `sun_path` holds 104 bytes including the terminating NUL.
    public static let sunPathCapacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)

    public static func socketName(pid: Int32) -> String {
        "e-\(pid).sock"
    }

    /// Shared with the CLI runtime-control socket: `~/Library/Application Support/KeyPath/control`.
    public static var primaryDirectory: URL {
        RuntimeControl.directoryURL
    }

    /// The per-user temporary directory macOS creates 0700 for this user.
    public static var fallbackDirectory: URL? {
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, length) > 0 else { return nil }
        let base = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(fileURLWithPath: base, isDirectory: true)
            .appendingPathComponent("KeyPath-control", isDirectory: true)
    }

    static func fits(_ path: String) -> Bool {
        path.utf8.count < sunPathCapacity
    }

    /// The primary location when the full path fits in `sun_path`, otherwise
    /// the fallback. Never truncates.
    public static func choosePath(name: String, primary: URL, fallback: URL?) throws -> (directory: URL, path: String) {
        let primaryPath = primary.appendingPathComponent(name).path
        if fits(primaryPath) { return (primary, primaryPath) }
        if let fallback {
            let fallbackPath = fallback.appendingPathComponent(name).path
            if fits(fallbackPath) { return (fallback, fallbackPath) }
        }
        throw SetupError.pathTooLong
    }

    /// Creates the directory 0700 and refuses one that is not a real directory
    /// owned by this user (a symlink, or one another user created first).
    public static func prepareDirectory(_ directory: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw SetupError.directory("could not be created: \(error.localizedDescription)")
        }
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
            throw SetupError.directory("not a directory")
        }
        guard info.st_uid == getuid() else {
            throw SetupError.directory("not owned by this user")
        }
        guard chmod(directory.path, 0o700) == 0 else {
            throw SetupError.directory("could not be made private")
        }
    }

    /// Removes sockets left by workers that are no longer running. A file that
    /// is not a socket, or names a live PID, is left alone.
    public static func removeStaleSockets(in directory: URL, isAlive: (Int32) -> Bool) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names {
            guard name.hasPrefix("e-"), name.hasSuffix(".sock"),
                  let pid = Int32(name.dropFirst(2).dropLast(5)), pid > 0, !isAlive(pid)
            else { continue }
            let path = directory.appendingPathComponent(name).path
            var info = stat()
            guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK else { continue }
            unlink(path)
        }
    }

    /// Binds and listens at `path`, replacing a stale socket file there. The
    /// socket is made 0600 and is not inherited by child processes. Until the
    /// chmod, the 0700 directory is what keeps others out; the umask is not
    /// changed, because it is process-wide.
    public static func bind(path: String) throws -> Int32 {
        var info = stat()
        if lstat(path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFSOCK else { throw SetupError.socket("path exists and is not a socket") }
            unlink(path)
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SetupError.socket("socket() failed: \(errno)") }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        guard var address = try? RuntimeControl.makeAddress(path) else {
            close(fd)
            throw SetupError.pathTooLong
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
            let error = errno
            close(fd)
            throw SetupError.socket("bind/listen failed: \(String(cString: strerror(error)))")
        }
        return fd
    }

    /// Everything the worker needs: choose the path, prepare the directory,
    /// clear stale sockets and bind.
    public static func open(
        pid: Int32 = getpid(),
        primary: URL = primaryDirectory,
        fallback: URL? = fallbackDirectory,
        isAlive: (Int32) -> Bool = { SystemStateProvider.isProcessAlive(pid: $0) }
    ) throws -> Listener {
        let (directory, path) = try choosePath(name: socketName(pid: pid), primary: primary, fallback: fallback)
        try prepareDirectory(directory)
        removeStaleSockets(in: directory, isAlive: isAlive)
        return try Listener(fd: bind(path: path), path: path)
    }

    /// This process's PID version, from its audit token. It changes when a
    /// PID is reused, so the app passes it to the worker with its PID.
    public static func currentPIDVersion() -> UInt32? {
        var token = audit_token_t()
        var count = mach_msg_type_number_t(MemoryLayout<audit_token_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &token) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return token.val.7
    }
}
