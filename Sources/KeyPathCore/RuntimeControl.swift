import Darwin
import Foundation

/// Local control channel between `keypath` (the CLI) and the running KeyPath app.
///
/// The driverless runtime lives inside the app's own session worker, so only the
/// app knows whether remapping is really running and only the app can start or
/// stop it. The app listens on a Unix-domain socket in a private directory and
/// accepts connections from the same user only; the CLI sends one JSON request
/// line and reads one JSON response line.
public enum RuntimeControl {
    public enum Operation: String, Codable, Sendable, CaseIterable {
        case status, start, stop, restart
        /// Full health check from inside the app: permissions, runtime, config.
        case doctor
        /// The app's own repair, then start remapping if nothing needs the user.
        case repair
        /// The app's own uninstall (backup, restore the keyboard, remove data,
        /// move the app to the Trash). Refused unless `confirmed` is true.
        case uninstall
    }

    public struct Request: Codable, Sendable, Equatable {
        public let operation: Operation
        public let reason: String?
        public let confirmed: Bool?

        public init(operation: Operation, reason: String? = nil, confirmed: Bool? = nil) {
            self.operation = operation
            self.reason = reason
            self.confirmed = confirmed
        }
    }

    /// One problem the app found, with the fix. `needsUser` marks the ones only
    /// a person can do (macOS permission switches); `settingsURL` opens the pane.
    public struct Issue: Codable, Sendable, Equatable {
        public let title: String
        public let category: String
        public let fix: String
        public let needsUser: Bool
        public let settingsURL: String?

        public init(title: String, category: String, fix: String, needsUser: Bool, settingsURL: String?) {
            self.title = title
            self.category = category
            self.fix = fix
            self.needsUser = needsUser
            self.settingsURL = settingsURL
        }
    }

    /// The runtime as the app sees it, after the requested operation finished.
    public enum State: String, Codable, Sendable {
        case running, starting, stopped, failed, unknown
    }

    public struct Response: Codable, Sendable, Equatable {
        /// The requested operation succeeded (always true for `status`).
        public let ok: Bool
        public let operation: Operation
        public let state: State
        public let workerPID: Int?
        /// Why the runtime is not running, when the app knows.
        public let failure: String?
        /// The app's most recent user-facing error, if any.
        public let lastError: String?
        public let layer: String?
        public let appPID: Int32
        public let appVersion: String
        /// doctor/repair: whether the whole system is ready, and what is not.
        public var ready: Bool?
        public var issues: [Issue]?
        /// repair/uninstall: what happened, e.g. where the uninstall backup went.
        public var message: String?

        public init(ok: Bool, operation: Operation, state: State, workerPID: Int?, failure: String?,
                    lastError: String?, layer: String?, appPID: Int32, appVersion: String,
                    ready: Bool? = nil, issues: [Issue]? = nil, message: String? = nil)
        {
            self.ready = ready
            self.issues = issues
            self.message = message
            self.ok = ok
            self.operation = operation
            self.state = state
            self.workerPID = workerPID
            self.failure = failure
            self.lastError = lastError
            self.layer = layer
            self.appPID = appPID
            self.appVersion = appVersion
        }
    }

    public enum ClientError: Error, Equatable, Sendable {
        /// No app is listening: it is not running, or predates this channel.
        case appNotRunning
        case timedOut
        case protocolError(String)
    }

    /// Requests and responses are one line each; nothing legitimate comes close.
    public static let maxMessageBytes = 64 * 1024

    public static var directoryURL: URL {
        AppPaths.applicationSupportDirectory.appendingPathComponent("control", isDirectory: true)
    }

    public static var socketURL: URL {
        directoryURL.appendingPathComponent("runtime.sock")
    }

    // MARK: - Client

    /// Send one request and wait for the app's answer. Start, stop and restart
    /// return only after the app has finished the operation, so allow time for it.
    public static func send(_ request: Request, timeout: TimeInterval, socketPath: String = socketURL.path) throws -> Response {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ClientError.protocolError("socket() failed: \(errno)") }
        defer { close(fd) }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        setTimeouts(fd, seconds: timeout)

        var address = try makeAddress(socketPath)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            if errno == ENOENT || errno == ECONNREFUSED { throw ClientError.appNotRunning }
            throw ClientError.protocolError("connect() failed: \(errno)")
        }

        var payload = try JSONEncoder().encode(request)
        payload.append(0x0A)
        try writeAll(fd, payload)
        let line = try readLine(fd)
        do { return try JSONDecoder().decode(Response.self, from: line) }
        catch { throw ClientError.protocolError("Unreadable response from KeyPath") }
    }

    // MARK: - Shared socket helpers

    public static func makeAddress(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw ClientError.protocolError("Socket path too long") }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }

    public static func setTimeouts(_ fd: Int32, seconds: TimeInterval) {
        var value = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - floor(seconds)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    public static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    if errno == EAGAIN { throw ClientError.timedOut }
                    throw ClientError.protocolError("write() failed: \(errno)")
                }
                offset += written
            }
        }
    }

    /// Read up to the first newline. Fails on timeout, EOF or an oversized line.
    public static func readLine(_ fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN { throw ClientError.timedOut }
                throw ClientError.protocolError("read() failed: \(errno)")
            }
            if count == 0 { throw ClientError.protocolError("KeyPath closed the connection") }
            if let newline = buffer[..<count].firstIndex(of: 0x0A) {
                data.append(contentsOf: buffer[..<newline])
                return data
            }
            data.append(contentsOf: buffer[..<count])
            guard data.count <= maxMessageBytes else { throw ClientError.protocolError("Message too large") }
        }
    }
}
