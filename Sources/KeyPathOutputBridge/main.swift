import Darwin
import Foundation
import KeyPathCore
import os

private struct CompanionPreparedSession: Codable, Sendable {
    let sessionID: String
    let socketPath: String
    let hostPID: Int32
    let hostUID: UInt32
    let hostGID: UInt32

    var session: KanataOutputBridgeSession {
        KanataOutputBridgeSession(
            sessionID: sessionID,
            socketPath: socketPath,
            socketDirectory: (socketPath as NSString).deletingLastPathComponent,
            hostPID: hostPID,
            hostUID: hostUID,
            hostGID: hostGID
        )
    }
}

private struct OutputBridgeFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? {
        message
    }
}

private enum OutputBridgeEmitter {
    private static let outputReadyTimeoutMillis: UInt64 = 5000
    private static let logger = Logger(subsystem: KeyPathConstants.Bundle.outputBridgeID, category: "emitter")
    private nonisolated(unsafe) static var cachedBridgeHandle: UnsafeMutableRawPointer?
    private nonisolated(unsafe) static var outputSinkInitialized = false

    private typealias EmitKeyFunction = @convention(c) (
        UInt32,
        UInt32,
        Bool,
        UnsafeMutablePointer<CChar>?,
        Int
    ) -> Bool
    private typealias InitializeOutputSinkFunction = @convention(c) (
        UnsafeMutablePointer<CChar>?,
        Int
    ) -> Bool
    private typealias OutputReadyFunction = @convention(c) () -> Bool
    private typealias WaitUntilOutputReadyFunction = @convention(c) (UInt64) -> Bool

    static func emitKey(_ event: KanataOutputBridgeKeyEvent) -> Result<Void, OutputBridgeFailure> {
        switch ensureOutputReady() {
        case .success:
            break
        case let .failure(error):
            return .failure(error)
        }

        switch emitKeyOnce(event) {
        case .success:
            return .success(())
        case let .failure(error):
            guard error.message.contains("sink disconnected") else {
                return .failure(error)
            }

            switch ensureOutputReady(forceActivate: true) {
            case .success:
                break
            case let .failure(activationError):
                return .failure(activationError)
            }

            return emitKeyOnce(event)
        }
    }

    static func syncModifiers(
        from current: KanataOutputBridgeModifierState,
        to desired: KanataOutputBridgeModifierState
    ) -> Result<Void, OutputBridgeFailure> {
        for event in modifierTransitions(from: current, to: desired) {
            switch emitKey(event) {
            case .success:
                continue
            case let .failure(error):
                return .failure(error)
            }
        }
        return .success(())
    }

    static func reset() -> Result<Void, OutputBridgeFailure> {
        let result = run("/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager", ["activate"])
        guard result.status == 0 else {
            return .failure(.init(message: result.out.isEmpty ? "failed to activate Karabiner VirtualHID manager" : result.out))
        }
        outputSinkInitialized = false
        return ensureOutputReady(forceActivate: true)
    }

    private static func ensureOutputReady(forceActivate: Bool = false) -> Result<Void, OutputBridgeFailure> {
        withBridgeFunctions { initializeOutputSink, _, outputReady, waitUntilReady in
            if !outputSinkInitialized || forceActivate {
                var errorBuffer = [CChar](repeating: 0, count: 2048)
                let initialized = initializeOutputSink(&errorBuffer, errorBuffer.count)
                guard initialized else {
                    return .failure(.init(message: decodeCStringBuffer(errorBuffer) ?? "failed to initialize DriverKit output sink"))
                }
                outputSinkInitialized = true
            }

            if outputReady() {
                return .success(())
            }

            guard waitUntilReady(outputReadyTimeoutMillis) else {
                return .failure(.init(message: "DriverKit virtual keyboard not ready after waiting \(outputReadyTimeoutMillis)ms"))
            }
            return .success(())
        }
    }

    private static func emitKeyOnce(_ event: KanataOutputBridgeKeyEvent) -> Result<Void, OutputBridgeFailure> {
        withBridgeFunctions { _, emitKey, _, _ in
            var errorBuffer = [CChar](repeating: 0, count: 2048)
            let success = emitKey(event.usagePage, event.usage, event.action == .keyDown, &errorBuffer, errorBuffer.count)
            return success
                ? .success(())
                : .failure(.init(message: decodeCStringBuffer(errorBuffer) ?? "unknown output bridge emit failure"))
        }
    }

    private static func withBridgeFunctions<T>(
        _ body: (InitializeOutputSinkFunction, EmitKeyFunction, OutputReadyFunction, WaitUntilOutputReadyFunction) -> Result<T, OutputBridgeFailure>
    ) -> Result<T, OutputBridgeFailure> {
        guard let handle = bridgeHandle() else {
            return .failure(.init(message: "failed to load host bridge"))
        }

        guard let initializeSymbol = dlsym(handle, "keypath_kanata_bridge_initialize_output_sink"),
              let emitSymbol = dlsym(handle, "keypath_kanata_bridge_emit_key"),
              let outputReadySymbol = dlsym(handle, "keypath_kanata_bridge_output_ready"),
              let waitUntilReadySymbol = dlsym(handle, "keypath_kanata_bridge_wait_until_output_ready")
        else {
            return .failure(.init(message: dlerror().map { String(cString: $0) } ?? "missing output bridge symbol"))
        }

        let initializeOutputSink = unsafeBitCast(initializeSymbol, to: InitializeOutputSinkFunction.self)
        let emitKey = unsafeBitCast(emitSymbol, to: EmitKeyFunction.self)
        let outputReady = unsafeBitCast(outputReadySymbol, to: OutputReadyFunction.self)
        let waitUntilReady = unsafeBitCast(waitUntilReadySymbol, to: WaitUntilOutputReadyFunction.self)
        return body(initializeOutputSink, emitKey, outputReady, waitUntilReady)
    }

    private static func bridgeHandle() -> UnsafeMutableRawPointer? {
        if let cachedBridgeHandle { return cachedBridgeHandle }
        let bridgePath = "/Applications/KeyPath.app/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib"
        guard FileManager.default.fileExists(atPath: bridgePath), let handle = dlopen(bridgePath, RTLD_NOW | RTLD_LOCAL) else {
            return nil
        }
        cachedBridgeHandle = handle
        return handle
    }

    private static func decodeCStringBuffer(_ buffer: [CChar]) -> String? {
        let bytes = buffer.map(UInt8.init(bitPattern:))
        let endIndex = bytes.firstIndex(of: 0) ?? bytes.endIndex
        let decoded = String(decoding: bytes[..<endIndex], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }

    private static func modifierTransitions(
        from current: KanataOutputBridgeModifierState,
        to desired: KanataOutputBridgeModifierState
    ) -> [KanataOutputBridgeKeyEvent] {
        let mappings: [(Bool, Bool, UInt32)] = [
            (current.leftControl, desired.leftControl, 0xE0),
            (current.leftShift, desired.leftShift, 0xE1),
            (current.leftAlt, desired.leftAlt, 0xE2),
            (current.leftCommand, desired.leftCommand, 0xE3),
            (current.rightControl, desired.rightControl, 0xE4),
            (current.rightShift, desired.rightShift, 0xE5),
            (current.rightAlt, desired.rightAlt, 0xE6),
            (current.rightCommand, desired.rightCommand, 0xE7),
        ]

        var events: [KanataOutputBridgeKeyEvent] = []
        var sequence: UInt64 = 1

        for mapping in mappings where mapping.0 && !mapping.1 {
            events.append(.init(usagePage: 0x07, usage: mapping.2, action: .keyUp, sequence: sequence))
            sequence += 1
        }

        for mapping in mappings where !mapping.0 && mapping.1 {
            events.append(.init(usagePage: 0x07, usage: mapping.2, action: .keyDown, sequence: sequence))
            sequence += 1
        }

        return events
    }

    private static func run(_ path: String, _ arguments: [String]) -> (status: Int32, out: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (1, error.localizedDescription)
        }
    }
}

private final class CompanionServer: @unchecked Sendable {
    private struct PeerCredentials {
        let uid: uid_t
        let gid: gid_t
        let pid: pid_t
    }

    private let session: KanataOutputBridgeSession
    private let queue: DispatchQueue
    private var listenerFD: Int32 = -1
    private var started = false
    private var currentModifierState = KanataOutputBridgeModifierState()

    init(session: KanataOutputBridgeSession) {
        self.session = session
        queue = DispatchQueue(label: "com.keypath.output-bridge.\(session.sessionID)")
    }

    func startIfNeeded() throws {
        guard !started else { return }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "KeyPathOutputBridge", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "failed to create output bridge socket: \(errno)"])
        }

        _ = unlink(session.socketPath)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxCount = MemoryLayout.size(ofValue: address.sun_path)
        guard session.socketPath.utf8.count < maxCount else {
            close(fd)
            throw NSError(domain: "KeyPathOutputBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "output bridge socket path too long"])
        }

        withUnsafeMutablePointer(to: &address.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            _ = session.socketPath.withCString { source in
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
            throw NSError(domain: "KeyPathOutputBridge", code: Int(code), userInfo: [NSLocalizedDescriptionKey: "failed to bind output bridge socket: \(code)"])
        }

        chown(session.socketPath, uid_t(session.hostUID), gid_t(session.hostGID))
        chmod(session.socketPath, 0o600)

        guard listen(fd, 8) == 0 else {
            let code = errno
            close(fd)
            throw NSError(domain: "KeyPathOutputBridge", code: Int(code), userInfo: [NSLocalizedDescriptionKey: "failed to listen on output bridge socket: \(code)"])
        }

        listenerFD = fd
        started = true
        queue.async { [self] in acceptLoop() }
    }

    func stop() {
        guard started else {
            _ = unlink(session.socketPath)
            return
        }
        started = false
        if listenerFD >= 0 {
            shutdown(listenerFD, SHUT_RDWR)
            close(listenerFD)
            listenerFD = -1
        }
        _ = unlink(session.socketPath)
    }

    private func acceptLoop() {
        while started {
            let clientFD = accept(listenerFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                if !started { break }
                continue
            }
            handle(clientFD: clientFD)
            close(clientFD)
        }
    }

    private func handle(clientFD: Int32) {
        do {
            let credentials = try peerCredentials(for: clientFD)
            var authenticated = false
            while true {
                let request = try readRequest(from: clientFD)
                let response: KanataOutputBridgeResponse
                let keepOpen: Bool

                switch request {
                case let .handshake(handshake):
                    if handshake.sessionID != session.sessionID {
                        response = .error(.init(code: "invalid_session", message: "handshake session mismatch", detail: "expected sessionID \(session.sessionID)"))
                    } else if handshake.hostPID != session.hostPID {
                        response = .error(.init(code: "invalid_host_pid", message: "handshake host PID mismatch", detail: "expected hostPID \(session.hostPID)"))
                    } else if credentials.uid != uid_t(session.hostUID) || credentials.gid != gid_t(session.hostGID) {
                        response = .error(.init(code: "invalid_peer", message: "socket peer credentials did not match prepared host", detail: "expected uid/gid \(session.hostUID):\(session.hostGID)"))
                    } else if credentials.pid != pid_t(session.hostPID) {
                        response = .error(.init(code: "invalid_peer_pid", message: "socket peer PID did not match prepared host", detail: "expected pid \(session.hostPID)"))
                    } else {
                        authenticated = true
                        response = .ready(version: KanataOutputBridgeProtocol.version)
                    }
                    keepOpen = true
                case .ping:
                    response = .pong
                    keepOpen = false
                case let .emitKey(event):
                    guard authenticated else {
                        try writeResponse(.error(.init(code: "unauthenticated", message: "output bridge handshake required before privileged requests")), to: clientFD)
                        return
                    }
                    switch OutputBridgeEmitter.emitKey(event) {
                    case .success:
                        response = .acknowledged(sequence: event.sequence)
                    case let .failure(error):
                        response = .error(.init(code: "emit_key_failed", message: "failed to emit key through privileged output bridge", detail: error.message))
                    }
                    keepOpen = false
                case let .syncModifiers(modifiers):
                    guard authenticated else {
                        try writeResponse(.error(.init(code: "unauthenticated", message: "output bridge handshake required before privileged requests")), to: clientFD)
                        return
                    }
                    switch OutputBridgeEmitter.syncModifiers(from: currentModifierState, to: modifiers) {
                    case .success:
                        currentModifierState = modifiers
                        response = .acknowledged(sequence: nil)
                    case let .failure(error):
                        response = .error(.init(code: "sync_modifiers_failed", message: "failed to sync modifier state through privileged output bridge", detail: error.message))
                    }
                    keepOpen = false
                case .reset:
                    guard authenticated else {
                        try writeResponse(.error(.init(code: "unauthenticated", message: "output bridge handshake required before privileged requests")), to: clientFD)
                        return
                    }
                    switch OutputBridgeEmitter.reset() {
                    case .success:
                        currentModifierState = .init()
                        response = .acknowledged(sequence: nil)
                    case let .failure(error):
                        response = .error(.init(code: "vhid_activate_failed", message: "failed to reset privileged output bridge", detail: error.message))
                    }
                    keepOpen = false
                }

                try writeResponse(response, to: clientFD)
                guard keepOpen else { return }
            }
        } catch {
            let response = KanataOutputBridgeResponse.error(.init(code: "server_error", message: "output bridge request handling failed", detail: error.localizedDescription))
            try? writeResponse(response, to: clientFD)
        }
    }

    private func peerCredentials(for fd: Int32) throws -> PeerCredentials {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else {
            throw NSError(domain: "KeyPathOutputBridge", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "failed to read peer uid/gid: \(errno)"])
        }

        var pid: pid_t = 0
        var pidSize = socklen_t(MemoryLayout<pid_t>.size)
        let pidResult = withUnsafeMutablePointer(to: &pid) { pidPtr in
            getsockopt(fd, 0, LOCAL_PEERPID, pidPtr, &pidSize)
        }
        guard pidResult == 0 else {
            throw NSError(domain: "KeyPathOutputBridge", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "failed to read peer pid: \(errno)"])
        }

        return PeerCredentials(uid: uid, gid: gid, pid: pid)
    }

    private func readRequest(from fd: Int32) throws -> KanataOutputBridgeRequest {
        var buffer = Data()
        var byte: UInt8 = 0
        while true {
            let result = Darwin.read(fd, &byte, 1)
            if result < 0 {
                throw NSError(domain: "KeyPathOutputBridge", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "output bridge read failed: \(errno)"])
            }
            if result == 0 {
                throw NSError(domain: "KeyPathOutputBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "output bridge client disconnected"])
            }
            buffer.append(byte)
            if byte == 0x0A {
                return try KanataOutputBridgeCodec.decode(buffer, as: KanataOutputBridgeRequest.self)
            }
        }
    }

    private func writeResponse(_ response: KanataOutputBridgeResponse, to fd: Int32) throws {
        let data = try KanataOutputBridgeCodec.encode(response)
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var bytesRemaining = rawBuffer.count
            var offset = 0
            while bytesRemaining > 0 {
                let written = Darwin.write(fd, baseAddress.advanced(by: offset), bytesRemaining)
                if written < 0 {
                    throw NSError(domain: "KeyPathOutputBridge", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "output bridge write failed: \(errno)"])
                }
                bytesRemaining -= written
                offset += written
            }
        }
    }
}

private final class OutputBridgeCompanion {
    private let logger = Logger(subsystem: KeyPathConstants.Bundle.outputBridgeID, category: "daemon")
    private var servers: [String: CompanionServer] = [:]

    func run() throws -> Never {
        try ensureDirectories()
        logger.info("starting output bridge companion")
        while true {
            reconcileSessions()
            sleep(1)
        }
    }

    private func reconcileSessions() {
        let sessions = loadSessions()
        let liveSessionIDs = Set(sessions.map(\.sessionID))

        for (sessionID, server) in servers where !liveSessionIDs.contains(sessionID) {
            server.stop()
            servers.removeValue(forKey: sessionID)
        }

        for session in sessions {
            guard isProcessAlive(session.hostPID) else {
                retireSessionFile(session.sessionID)
                continue
            }

            if servers[session.sessionID] == nil {
                let server = CompanionServer(session: session)
                do {
                    try server.startIfNeeded()
                    servers[session.sessionID] = server
                    logger.info("activated output bridge session \(session.sessionID, privacy: .public)")
                } catch {
                    logger.error("failed to activate output bridge session \(session.sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func loadSessions() -> [KanataOutputBridgeSession] {
        let dir = URL(fileURLWithPath: KeyPathConstants.OutputBridge.sessionDirectory, isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))
            ?? []
        return files.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(CompanionPreparedSession.self, from: data)
            else {
                return nil
            }
            return record.session
        }
    }

    private func ensureDirectories() throws {
        let fileManager = FileManager.default
        for path in [KeyPathConstants.OutputBridge.runDirectory, KeyPathConstants.OutputBridge.socketDirectory, KeyPathConstants.OutputBridge.sessionDirectory] {
            if !fileManager.fileExists(atPath: path) {
                try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
            }
        }
        chmod(KeyPathConstants.OutputBridge.runDirectory, 0o755)
        // 0755 (not 0711): user-mode kanata-launcher needs read+execute to connect
        // to the Unix socket. Execute-only (0711) blocks socket discovery by non-root.
        chmod(KeyPathConstants.OutputBridge.socketDirectory, 0o755)
        chmod(KeyPathConstants.OutputBridge.sessionDirectory, 0o700)
    }

    private func retireSessionFile(_ sessionID: String) {
        let path = (KeyPathConstants.OutputBridge.sessionDirectory as NSString).appendingPathComponent("\(sessionID).json")
        try? FileManager.default.removeItem(atPath: path)
        if let server = servers.removeValue(forKey: sessionID) {
            server.stop()
        }
    }

    private func isProcessAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}

do {
    try OutputBridgeCompanion().run()
} catch {
    FileHandle.standardError.write(Data("[keypath-output-bridge] fatal: \(error.localizedDescription)\n".utf8))
    Foundation.exit(1)
}
