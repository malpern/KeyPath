import Darwin
import Foundation

public enum KanataOutputBridgeClientError: Error, Equatable, LocalizedError {
    case socketCreationFailed(Int32)
    case invalidSocketPath
    case connectFailed(Int32)
    case socketNotFound(String)
    case socketNotListening(String)
    case writeFailed(Int32)
    case readFailed(Int32)
    case connectionClosed
    case unexpectedResponse

    public var errorDescription: String? {
        switch self {
        case let .socketCreationFailed(code):
            "Failed to create UNIX socket (\(code))"
        case .invalidSocketPath:
            "Invalid UNIX socket path"
        case let .connectFailed(code):
            "Failed to connect to output bridge socket (\(code))"
        case let .socketNotFound(path):
            "Output bridge socket not found at \(path). Prepare a fresh bridge session and try again."
        case let .socketNotListening(path):
            "Output bridge socket at \(path) is stale or not listening. Prepare a fresh bridge session and try again."
        case let .writeFailed(code):
            "Failed to write to output bridge socket (\(code))"
        case let .readFailed(code):
            "Failed to read from output bridge socket (\(code))"
        case .connectionClosed:
            "Output bridge socket closed unexpectedly"
        case .unexpectedResponse:
            "Output bridge returned an unexpected response"
        }
    }
}

public enum KanataOutputBridgeClient {
    public static func performHandshake(
        session: KanataOutputBridgeSession
    ) throws -> KanataOutputBridgeResponse {
        let fd = try connect(to: session.socketPath)
        defer { close(fd) }

        try send(.handshake(.init(sessionID: session.sessionID, hostPID: session.hostPID)), over: fd)
        return try receive(from: fd)
    }

    public static func ping(session: KanataOutputBridgeSession) throws -> KanataOutputBridgeResponse {
        let fd = try authenticatedConnect(session: session)
        defer { close(fd) }

        try send(.ping, over: fd)
        return try receive(from: fd)
    }

    public static func smokeTest(
        session: KanataOutputBridgeSession
    ) throws -> (handshake: KanataOutputBridgeResponse, ping: KanataOutputBridgeResponse) {
        let handshake = try performHandshake(session: session)
        let ping = try ping(session: session)
        return (handshake, ping)
    }

    public static func emitKey(
        _ event: KanataOutputBridgeKeyEvent,
        session: KanataOutputBridgeSession
    ) throws -> KanataOutputBridgeResponse {
        let fd = try authenticatedConnect(session: session)
        defer { close(fd) }

        try send(.emitKey(event), over: fd)
        return try receive(from: fd)
    }

    public static func syncModifiers(
        _ state: KanataOutputBridgeModifierState,
        session: KanataOutputBridgeSession
    ) throws -> KanataOutputBridgeResponse {
        let fd = try authenticatedConnect(session: session)
        defer { close(fd) }

        try send(.syncModifiers(state), over: fd)
        return try receive(from: fd)
    }

    public static func reset(session: KanataOutputBridgeSession) throws -> KanataOutputBridgeResponse {
        let fd = try authenticatedConnect(session: session)
        defer { close(fd) }

        try send(.reset, over: fd)
        return try receive(from: fd)
    }

    private static func authenticatedConnect(session: KanataOutputBridgeSession) throws -> Int32 {
        let fd = try connect(to: session.socketPath)
        do {
            try send(.handshake(.init(sessionID: session.sessionID, hostPID: session.hostPID)), over: fd)
            let response = try receive(from: fd)
            guard case .ready = response else {
                close(fd)
                throw KanataOutputBridgeClientError.unexpectedResponse
            }
            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    public static func connect(to socketPath: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw KanataOutputBridgeClientError.socketCreationFailed(errno)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let maxCount = MemoryLayout.size(ofValue: address.sun_path)
        guard socketPath.utf8.count < maxCount else {
            close(fd)
            throw KanataOutputBridgeClientError.invalidSocketPath
        }

        withUnsafeMutablePointer(to: &address.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            _ = socketPath.withCString { source in
                strncpy(raw, source, maxCount - 1)
            }
        }

        let length = socklen_t(MemoryLayout.size(ofValue: address))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, length)
            }
        }
        guard result == 0 else {
            let code = errno
            close(fd)
            switch code {
            case ENOENT:
                throw KanataOutputBridgeClientError.socketNotFound(socketPath)
            case ECONNREFUSED:
                throw KanataOutputBridgeClientError.socketNotListening(socketPath)
            default:
                throw KanataOutputBridgeClientError.connectFailed(code)
            }
        }

        return fd
    }

    public static func send(_ request: KanataOutputBridgeRequest, over fd: Int32) throws {
        let data = try KanataOutputBridgeCodec.encode(request)
        try writeAll(data, to: fd)
    }

    public static func receive(from fd: Int32) throws -> KanataOutputBridgeResponse {
        let data = try readLine(from: fd)
        return try KanataOutputBridgeCodec.decode(data, as: KanataOutputBridgeResponse.self)
    }

    private static func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var bytesRemaining = rawBuffer.count
            var offset = 0

            while bytesRemaining > 0 {
                let written = Darwin.write(fd, baseAddress.advanced(by: offset), bytesRemaining)
                if written < 0 {
                    throw KanataOutputBridgeClientError.writeFailed(errno)
                }
                bytesRemaining -= written
                offset += written
            }
        }
    }

    private static func readLine(from fd: Int32) throws -> Data {
        var buffer = Data()
        var byte: UInt8 = 0

        while true {
            let result = Darwin.read(fd, &byte, 1)
            if result < 0 {
                throw KanataOutputBridgeClientError.readFailed(errno)
            }
            if result == 0 {
                if buffer.isEmpty {
                    throw KanataOutputBridgeClientError.connectionClosed
                }
                return buffer
            }

            buffer.append(byte)
            if byte == 0x0A {
                return buffer
            }
        }
    }
}
