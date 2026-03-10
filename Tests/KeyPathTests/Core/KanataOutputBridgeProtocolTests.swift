import Darwin
import Foundation
import KeyPathCore
@preconcurrency import XCTest

final class KanataOutputBridgeProtocolTests: XCTestCase {
    func testHandshakeRequestRoundTripsThroughJSON() throws {
        let request = KanataOutputBridgeRequest.handshake(
            KanataOutputBridgeHandshake(sessionID: "session-123", hostPID: 4242)
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(KanataOutputBridgeRequest.self, from: data)

        XCTAssertEqual(decoded, request)
    }

    func testKeyEventRequestRoundTripsThroughJSON() throws {
        let request = KanataOutputBridgeRequest.emitKey(
            KanataOutputBridgeKeyEvent(
                usagePage: 0x07,
                usage: 0x04,
                action: .keyDown,
                sequence: 7
            )
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(KanataOutputBridgeRequest.self, from: data)

        XCTAssertEqual(decoded, request)
    }

    func testErrorResponseRoundTripsThroughJSON() throws {
        let response = KanataOutputBridgeResponse.error(
            KanataOutputBridgeError(
                code: "vhid_unavailable",
                message: "VirtualHID output is unavailable",
                detail: "root bridge not connected"
            )
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(KanataOutputBridgeResponse.self, from: data)

        XCTAssertEqual(decoded, response)
    }

    func testUnixSocketHandshakeAndProtocolOperations() throws {
        let socketPath = temporarySocketPath()
        defer { _ = unlink(socketPath) }

        let serverFD = try makeServerSocket(path: socketPath)
        defer { close(serverFD) }

        let handshakeExpectation = expectation(description: "handshake")
        handshakeExpectation.expectedFulfillmentCount = 5
        let pingExpectation = expectation(description: "ping")
        let emitExpectation = expectation(description: "emitKey")
        let modifiersExpectation = expectation(description: "syncModifiers")
        let resetExpectation = expectation(description: "reset")

        let server = DispatchQueue(label: "KanataOutputBridgeProtocolTests.server")
        server.async {
            for _ in 0 ..< 5 {
                let clientFD = accept(serverFD, nil, nil)
                XCTAssertGreaterThanOrEqual(clientFD, 0)
                defer { close(clientFD) }

                do {
                    var sawHandshake = false
                    while true {
                        let request: KanataOutputBridgeRequest
                        do {
                            request = try Self.readRequest(from: clientFD)
                        } catch KanataOutputBridgeClientError.connectionClosed where sawHandshake {
                            break
                        }
                        var shouldClose = false
                        switch request {
                        case let .handshake(handshake):
                            XCTAssertFalse(sawHandshake)
                            sawHandshake = true
                            XCTAssertEqual(handshake.sessionID, "session-123")
                            XCTAssertEqual(handshake.hostPID, 4242)
                            try Self.writeResponse(.ready(version: KanataOutputBridgeProtocol.version), to: clientFD)
                            handshakeExpectation.fulfill()
                        case .ping:
                            try Self.writeResponse(.pong, to: clientFD)
                            pingExpectation.fulfill()
                            shouldClose = true
                        case let .emitKey(event):
                            XCTAssertTrue(sawHandshake)
                            XCTAssertEqual(event.sequence, 7)
                            XCTAssertEqual(event.usagePage, 0x07)
                            XCTAssertEqual(event.usage, 0x04)
                            XCTAssertEqual(event.action, .keyDown)
                            try Self.writeResponse(.acknowledged(sequence: event.sequence), to: clientFD)
                            emitExpectation.fulfill()
                            shouldClose = true
                        case let .syncModifiers(modifiers):
                            XCTAssertTrue(sawHandshake)
                            XCTAssertTrue(modifiers.leftShift)
                            XCTAssertTrue(modifiers.rightCommand)
                            XCTAssertFalse(modifiers.leftControl)
                            try Self.writeResponse(.acknowledged(sequence: nil), to: clientFD)
                            modifiersExpectation.fulfill()
                            shouldClose = true
                        case .reset:
                            XCTAssertTrue(sawHandshake)
                            try Self.writeResponse(.acknowledged(sequence: nil), to: clientFD)
                            resetExpectation.fulfill()
                            shouldClose = true
                        }
                        if shouldClose {
                            break
                        }
                    }
                } catch {
                    XCTFail("Server error: \(error)")
                }
            }
        }

        let session = KanataOutputBridgeSession(
            sessionID: "session-123",
            socketPath: socketPath,
            socketDirectory: URL(fileURLWithPath: socketPath).deletingLastPathComponent().path,
            hostPID: 4242,
            hostUID: UInt32(getuid()),
            hostGID: UInt32(getgid())
        )

        let handshake = try KanataOutputBridgeClient.performHandshake(session: session)
        XCTAssertEqual(
            handshake,
            KanataOutputBridgeResponse.ready(version: KanataOutputBridgeProtocol.version)
        )

        let pong = try KanataOutputBridgeClient.ping(session: session)
        XCTAssertEqual(pong, KanataOutputBridgeResponse.pong)

        let emitAck = try KanataOutputBridgeClient.emitKey(
            KanataOutputBridgeKeyEvent(
                usagePage: 0x07,
                usage: 0x04,
                action: .keyDown,
                sequence: 7
            ),
            session: session
        )
        XCTAssertEqual(emitAck, KanataOutputBridgeResponse.acknowledged(sequence: 7))

        let modifiersAck = try KanataOutputBridgeClient.syncModifiers(
            KanataOutputBridgeModifierState(leftShift: true, rightCommand: true),
            session: session
        )
        XCTAssertEqual(modifiersAck, KanataOutputBridgeResponse.acknowledged(sequence: nil))

        let resetAck = try KanataOutputBridgeClient.reset(session: session)
        XCTAssertEqual(resetAck, KanataOutputBridgeResponse.acknowledged(sequence: nil))

        wait(
            for: [
                handshakeExpectation,
                pingExpectation,
                emitExpectation,
                modifiersExpectation,
                resetExpectation
            ],
            timeout: 2.0
        )
    }

    func testConnectToMissingSocketReturnsFreshSessionHint() throws {
        let socketPath = temporarySocketPath()
        _ = unlink(socketPath)

        XCTAssertThrowsError(try KanataOutputBridgeClient.connect(to: socketPath)) { error in
            XCTAssertEqual(
                error as? KanataOutputBridgeClientError,
                .socketNotFound(socketPath)
            )
        }
    }

    func testConnectToStaleSocketReturnsFreshSessionHint() throws {
        let socketPath = temporarySocketPath()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        guard fd >= 0 else { throw KanataOutputBridgeClientError.socketCreationFailed(errno) }
        defer {
            close(fd)
            _ = unlink(socketPath)
        }

        try bindSocket(fd, path: socketPath)

        XCTAssertThrowsError(try KanataOutputBridgeClient.connect(to: socketPath)) { error in
            XCTAssertEqual(
                error as? KanataOutputBridgeClientError,
                .socketNotListening(socketPath)
            )
        }
    }

    private func temporarySocketPath() -> String {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        return "/tmp/kp-bridge-\(suffix).sock"
    }

    private func makeServerSocket(path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        guard fd >= 0 else { throw KanataOutputBridgeClientError.socketCreationFailed(errno) }

        _ = unlink(path)

        try bindSocket(fd, path: path)

        guard listen(fd, 4) == 0 else {
            let code = errno
            close(fd)
            throw KanataOutputBridgeClientError.connectFailed(code)
        }

        return fd
    }

    private func bindSocket(_ fd: Int32, path: String) throws {
        _ = unlink(path)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxCount = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < maxCount else {
            close(fd)
            throw KanataOutputBridgeClientError.invalidSocketPath
        }

        withUnsafeMutablePointer(to: &address.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            _ = path.withCString { source in
                strncpy(raw, source, maxCount - 1)
            }
        }

        let addressLength = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(fd, sockaddrPtr, addressLength)
            }
        }
        guard bindResult == 0 else {
            let code = errno
            close(fd)
            throw KanataOutputBridgeClientError.connectFailed(code)
        }
    }

    private static func readRequest(from fd: Int32) throws -> KanataOutputBridgeRequest {
        var buffer = Data()
        var byte: UInt8 = 0
        while true {
            let result = Darwin.read(fd, &byte, 1)
            if result < 0 {
                throw KanataOutputBridgeClientError.readFailed(errno)
            }
            if result == 0 {
                throw KanataOutputBridgeClientError.connectionClosed
            }
            buffer.append(byte)
            if byte == 0x0A {
                return try KanataOutputBridgeCodec.decode(buffer, as: KanataOutputBridgeRequest.self)
            }
        }
    }

    private static func writeResponse(_ response: KanataOutputBridgeResponse, to fd: Int32) throws {
        let data = try KanataOutputBridgeCodec.encode(response)
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
}
