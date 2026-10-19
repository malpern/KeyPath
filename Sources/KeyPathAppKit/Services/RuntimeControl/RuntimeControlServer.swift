import Darwin
import Foundation
import KeyPathCore

/// The app side of `RuntimeControl`: a same-user Unix-domain socket the CLI uses
/// to ask for runtime status and to start, stop or restart remapping.
///
/// Every operation runs through the handler, which the composition root wires
/// to `RuntimeCoordinator` (and so to `ServiceLifecycleCoordinator`), the only
/// owner of the runtime lifecycle. The socket lives in a 0700 directory, is
/// created 0600, and each connection is refused unless its peer has this
/// process's uid.
@MainActor
final class RuntimeControlServer {
    static let shared = RuntimeControlServer()

    typealias Handler = @MainActor (RuntimeControl.Request) async -> RuntimeControl.Response

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.keypath.runtime-control")
    private var handler: Handler?

    /// Start listening. Safe to call once per process; later calls are ignored.
    func start(directory: URL = RuntimeControl.directoryURL, handler: @escaping Handler) {
        guard listenFD < 0 else { return }
        self.handler = handler
        do {
            listenFD = try Self.bindSocket(directory: directory)
        } catch {
            AppLogger.shared.warn("⚠️ [RuntimeControl] CLI control socket unavailable: \(error)")
            return
        }
        let source = Self.makeAcceptSource(fd: listenFD, queue: queue) { [weak self] client in
            Task { @MainActor [weak self] in
                guard let self else { close(client); return }
                await serve(client)
            }
        }
        acceptSource = source
        source.resume()
        AppLogger.shared.info("🎛️ [RuntimeControl] Listening for CLI requests")
    }

    /// Built outside the main actor: the handler runs on `queue`, and a closure
    /// formed in this @MainActor class would be main-actor isolated and trap there.
    private nonisolated static func makeAcceptSource(fd: Int32, queue: DispatchQueue,
                                                     onClient: @escaping @Sendable (Int32) -> Void) -> DispatchSourceRead
    {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler {
            let client = accept(fd, nil, nil)
            if client >= 0 { onClient(client) }
        }
        return source
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 { close(listenFD) }
        listenFD = -1
    }

    // MARK: - Connections

    private func serve(_ client: Int32) async {
        // Reading and writing block (bounded by timeouts), so keep them off the main actor.
        let request: RuntimeControl.Request? = await Self.offMain {
            var noSigPipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            RuntimeControl.setTimeouts(client, seconds: 5)
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
                AppLogger.shared.warn("⚠️ [RuntimeControl] Refused a connection from another user")
                return nil
            }
            guard let line = try? RuntimeControl.readLine(client) else { return nil }
            return try? JSONDecoder().decode(RuntimeControl.Request.self, from: line)
        }
        guard let request, let handler else {
            close(client)
            return
        }
        AppLogger.shared.info("🎛️ [RuntimeControl] CLI requested \(request.operation.rawValue)")
        let response = await handler(request)
        await Self.offMain {
            // Start and stop can take a while; the client waits with its own timeout.
            RuntimeControl.setTimeouts(client, seconds: 5)
            if var data = try? JSONEncoder().encode(response) {
                data.append(0x0A)
                try? RuntimeControl.writeAll(client, data)
            }
            close(client)
        }
    }

    private nonisolated static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work()) }
        }
    }

    // MARK: - Socket setup

    enum SetupError: Error {
        case directory(String), anotherInstance, socket(Int32)
    }

    /// Bind the listening socket. A stale socket file left by a crash is replaced;
    /// a socket another live app instance is serving is left alone.
    nonisolated static func bindSocket(directory: URL) throws -> Int32 {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid() else {
            throw SetupError.directory("not a directory owned by this user")
        }
        chmod(directory.path, 0o700)

        let path = directory.appendingPathComponent("runtime.sock").path
        if lstat(path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFSOCK else { throw SetupError.directory("socket path is not a socket") }
            let probe = try? RuntimeControl.send(.init(operation: .status), timeout: 1, socketPath: path)
            if probe != nil { throw SetupError.anotherInstance }
            unlink(path)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SetupError.socket(errno) }
        var address = try RuntimeControl.makeAddress(path)
        let previousMask = umask(0o177)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(previousMask)
        guard bound == 0, listen(fd, 8) == 0 else {
            let error = errno
            close(fd)
            throw SetupError.socket(error)
        }
        return fd
    }
}
