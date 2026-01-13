import Foundation
import KeyPathCore
import Network

/// ServerResponse matches the Rust protocol ServerResponse enum
/// Format: {"status":"Ok"} or {"status":"Error","msg":"..."}
struct TcpServerResponse: Codable, Sendable {
    let status: String
    let msg: String?

    enum CodingKeys: String, CodingKey {
        case status
        case msg
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        msg = try container.decodeIfPresent(String.self, forKey: .msg)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(msg, forKey: .msg)
    }

    var isOk: Bool {
        status == "Ok"
    }

    var isError: Bool {
        status == "Error"
    }
}

/// Simple completion flag for thread-safe continuation handling
private final class CompletionFlag: @unchecked Sendable {
    private var completed = false
    private let lock = NSLock()

    func markCompleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}

/// TCP client for communicating with Kanata's local TCP server
///
/// Design principles:
/// - Localhost IPC, not distributed networking
/// - Persistent TCP connection for reliability
/// - Simple timeout mechanism
/// - Connection pooling for efficiency
///
/// **SECURITY NOTE (ADR-013):**
/// Kanata v1.9.0 TCP server does NOT support authentication.
/// The tcp_server.rs code explicitly ignores Authenticate messages:
/// ```rust
/// ClientMessage::Authenticate { .. } => {
///     log::debug!("TCP server ignoring authentication message (not needed for TCP)");
///     continue;
/// }
/// ```
///
/// This means:
/// - No client identity verification
/// - Any local process can send commands to localhost:37001
/// - Limited attack surface: only config reloads, not arbitrary code execution
///
/// **Future Work:**
/// Consider contributing authentication support to upstream Kanata.
/// Design would mirror the UDP authentication (token-based, session expiry).
/// Until then, rely on localhost-only binding and OS-level process isolation.
actor KanataTCPClient {
    private let host: String
    private let port: Int
    private let timeout: TimeInterval
    private let retryBackoffSeconds: TimeInterval = 0.15

    // Connection management
    private var connection: NWConnection?
    private var isConnecting = false

    // MARK: - Read Buffer (Critical for Two-Line Protocol)

    //
    // **WHY THIS EXISTS:**
    // Kanata's TCP protocol sends TWO lines for Hello/Validate/Reload commands:
    //   Line 1: {"status":"Ok"}\n
    //   Line 2: {"HelloOk":...}\n or {"ValidationResult":...}\n or {"ReloadResult":...}\n
    //
    // These lines can arrive in a single TCP packet. Without buffering, the first
    // readUntilNewline() call would consume BOTH lines, then the second read would
    // hang forever waiting for data that was already discarded.
    //
    // **HOW IT WORKS:**
    // - readUntilNewline() always returns exactly ONE line (up to \n)
    // - Leftover data stays in readBuffer for subsequent calls
    // - Buffer is cleared when connection closes
    //
    // **TEST:** If you modify this, verify with: KEYPATH_ENABLE_TCP_TESTS=1 swift test
    // and manually test saving a key mapping (2→3) in the UI.
    private var readBuffer = Data()

    // Handshake cache
    private var cachedHello: TcpHelloOk?

    // Request ID management for reliable response correlation
    private var nextRequestId: UInt64 = 1

    /// Generate next request ID (monotonically increasing)
    private func generateRequestId() -> UInt64 {
        let id = nextRequestId
        nextRequestId += 1
        return id
    }

    // MARK: - Initialization

    /// Default timeout: 5 seconds for production, 0.1 seconds for tests
    private static var defaultTimeout: TimeInterval {
        TestEnvironment.isRunningTests ? 0.1 : 5.0
    }

    init(
        host: String = "127.0.0.1", port: Int, timeout: TimeInterval? = nil,
        reuseConnection _: Bool = true
    ) {
        self.host = host
        self.port = port
        self.timeout = timeout ?? Self.defaultTimeout
    }

    // MARK: - Connection Management

    private func ensureConnection() async throws -> NWConnection {
        // Attempt once, then single retry with small backoff on timeout/connection failure
        do {
            return try await ensureConnectionCore()
        } catch {
            if shouldRetry(error) {
                AppLogger.shared.debug("🌐 [TCP] ensureConnection retry after backoff: \(error)")
                try? await Task.sleep(nanoseconds: UInt64(retryBackoffSeconds * 1_000_000_000))
                // Reset any half-open state
                closeConnection()
                return try await ensureConnectionCore()
            }
            throw error
        }
    }

    private func ensureConnectionCore() async throws -> NWConnection {
        // Return existing connection if ready
        if let connection, connection.state == .ready {
            AppLogger.shared.log("🔌 [TCP] Reusing existing connection (state=\(connection.state))")
            return connection
        }

        // Log if we have a connection but it's not ready
        if let connection {
            AppLogger.shared.log("🔌 [TCP] Existing connection not ready (state=\(connection.state)), creating new one")
        } else {
            AppLogger.shared.log("🔌 [TCP] No existing connection, creating new one")
        }

        // Wait if already connecting
        while isConnecting {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        // Check again after waiting
        if let connection, connection.state == .ready {
            AppLogger.shared.log("🔌 [TCP] Connection became ready while waiting")
            return connection
        }

        // Create new connection
        isConnecting = true
        defer { isConnecting = false }

        AppLogger.shared.log("🔌 [TCP] Creating new connection to \(host):\(port)")
        let newConnection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .tcp
        )

        connection = newConnection

        // Wait for connection to be ready with timeout
        return try await withThrowingTaskGroup(of: NWConnection.self) { group in
            // Connection attempt task
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    let completionFlag = CompletionFlag()

                    newConnection.stateUpdateHandler = { state in
                        AppLogger.shared.log("🔌 [TCP] Connection state changed: \(state)")
                        switch state {
                        case .ready:
                            if completionFlag.markCompleted() {
                                continuation.resume(returning: newConnection)
                            }

                        case let .failed(error):
                            if completionFlag.markCompleted() {
                                continuation.resume(
                                    throwing: KeyPathError.communication(
                                        .connectionFailed(reason: error.localizedDescription)))
                            }
                            newConnection.cancel()

                        case .cancelled:
                            if completionFlag.markCompleted() {
                                continuation.resume(
                                    throwing: KeyPathError.communication(
                                        .connectionFailed(reason: "Connection cancelled")))
                            }

                        default:
                            break
                        }
                    }

                    newConnection.start(queue: .global())
                }
            }

            // Timeout task (use the configured timeout value)
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
                newConnection.cancel() // Cancel the connection on timeout
                throw KeyPathError.communication(.timeout)
            }

            // Return first result and cancel other task
            let result = try await group.next()!
            group.cancelAll()
            AppLogger.shared.log("🔌 [TCP] Connection established successfully")
            return result
        }
    }

    private func stateString(_ state: NWConnection.State?) -> String {
        guard let state else { return "nil" }
        switch state {
        case .setup: return "setup"
        case .waiting: return "waiting"
        case .preparing: return "preparing"
        case .ready: return "ready"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        @unknown default: return "unknown"
        }
    }

    private func closeConnection() {
        let currentState = stateString(connection?.state)
        AppLogger.shared.log("🔌 [TCP] closeConnection() called (current state=\(currentState))")

        // Log call stack for debugging (first 5 frames)
        let stackSymbols = Thread.callStackSymbols.prefix(5).joined(separator: "\n  ")
        AppLogger.shared.debug("🔌 [TCP] closeConnection() stack trace:\n  \(stackSymbols)")

        connection?.cancel()
        connection = nil
        readBuffer.removeAll() // Clear buffered data when connection closes
    }

    /// Cancel any ongoing operations and close connection
    func cancelInflightAndCloseConnection() {
        AppLogger.shared.debug("🔌 [TCP] Closing connection")
        closeConnection()
    }

    // FIX #3: Helper to execute operations with automatic error recovery
    /// Executes an operation and closes connection if it fails with a recoverable error
    private func withErrorRecovery<T: Sendable>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            // Close connection on timeout or connection failure so next call gets a fresh connection
            if shouldRetry(error) {
                AppLogger.shared.debug("🌐 [TCP] Operation failed with recoverable error, closing connection: \(error)")
                closeConnection()
            }
            throw error
        }
    }

    // MARK: - Server Operations

    // MARK: - Protocol Models

    struct TcpHelloOk: Codable, Sendable {
        let version: String
        let protocolVersion: Int
        let capabilities: [String]
        let request_id: UInt64?

        enum CodingKeys: String, CodingKey {
            case version
            case protocolVersion = "protocol"
            case capabilities
            case request_id
            // Minimal server compatibility
            case server
        }

        init(version: String, protocolVersion: Int, capabilities: [String], request_id: UInt64? = nil) {
            self.version = version
            self.protocolVersion = protocolVersion
            self.capabilities = capabilities
            self.request_id = request_id
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            request_id = try container.decodeIfPresent(UInt64.self, forKey: .request_id)

            if let version = try container.decodeIfPresent(String.self, forKey: .version),
               let protocolVersion = try container.decodeIfPresent(Int.self, forKey: .protocolVersion),
               let capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) {
                self.version = version
                self.protocolVersion = protocolVersion
                self.capabilities = capabilities
                return
            }

            // Minimal form: { "HelloOk": { "server": "kanata", "capabilities": [..] } }
            let serverString = try (container.decodeIfPresent(String.self, forKey: .server)) ?? "kanata"
            let caps = try (container.decodeIfPresent([String].self, forKey: .capabilities)) ?? []
            version = serverString
            protocolVersion = 1
            capabilities = caps
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(version, forKey: .version)
            try container.encode(protocolVersion, forKey: .protocolVersion)
            try container.encode(capabilities, forKey: .capabilities)
        }

        func hasCapabilities(_ required: [String]) -> Bool {
            let set = Set(capabilities)
            return required.allSatisfy { set.contains($0) }
        }
    }

    struct TcpLastReload: Codable, Sendable {
        let ok: Bool
        let at: String?
        let duration_ms: UInt64?
        let epoch: UInt64?
    }

    struct TcpStatusInfo: Codable, Sendable {
        let engine_version: String?
        let uptime_s: UInt64?
        let ready: Bool
        let last_reload: TcpLastReload?
        let request_id: UInt64?
    }

    struct TcpLayerNames: Codable, Sendable {
        let names: [String]
        let request_id: UInt64?
    }

    // MARK: - Handshake / Status

    /// Perform Hello handshake and cache capabilities.
    /// Kanata may emit a status line and/or broadcast lines before HelloOk.
    /// We parse HelloOk from the first response and fall back to reading
    /// additional lines only if needed.
    func hello() async throws -> TcpHelloOk {
        // FIX #3: Wrap operation with error recovery to clean up bad connections
        try await withErrorRecovery {
            if let cachedHello { return cachedHello }

            let requestId = generateRequestId()
            let requestData = try JSONEncoder().encode(["Hello": ["request_id": requestId]])
            let start = CFAbsoluteTimeGetCurrent()

            // Read first response (may already contain HelloOk)
            let firstLine = try await send(requestData)
            let firstLineStr = String(data: firstLine, encoding: .utf8) ?? ""
            AppLogger.shared.log("🌐 [TCP] Hello response: \(firstLineStr)")

            if let hello = try extractMessage(named: "HelloOk", into: TcpHelloOk.self, from: firstLine) {
                let dt = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                AppLogger.shared.log(
                    "✅ [TCP] hello ok (duration=\(dt)ms, protocol=\(hello.protocolVersion), caps=\(hello.capabilities.joined(separator: ",")))"
                )
                cachedHello = hello
                return hello
            }

            // Check if first line indicates error
            if let json = try? JSONSerialization.jsonObject(with: firstLine) as? [String: Any],
               let status = json["status"] as? String,
               status.lowercased() == "error" {
                let errorMsg = json["msg"] as? String ?? "Hello request failed"
                throw KeyPathError.communication(.connectionFailed(reason: errorMsg))
            }

            // Fallback: read additional lines until we find HelloOk or time out.
            let connection = try await ensureConnectionCore()
            let deadline = CFAbsoluteTimeGetCurrent() + 5.0
            var attempts = 0
            var lastLine = firstLine

            while CFAbsoluteTimeGetCurrent() < deadline, attempts < 5 {
                let remaining = max(0.1, deadline - CFAbsoluteTimeGetCurrent())
                let nextLine = try await withTimeout(seconds: remaining) {
                    try await self.readUntilNewline(on: connection)
                }
                attempts += 1
                lastLine = nextLine

                if isUnsolicitedBroadcast(nextLine) {
                    continue
                }

                if let hello = try extractMessage(named: "HelloOk", into: TcpHelloOk.self, from: nextLine) {
                    let dt = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                    AppLogger.shared.log(
                        "✅ [TCP] hello ok (duration=\(dt)ms, protocol=\(hello.protocolVersion), caps=\(hello.capabilities.joined(separator: ",")))"
                    )
                    cachedHello = hello
                    return hello
                }

                if let json = try? JSONSerialization.jsonObject(with: nextLine) as? [String: Any],
                   let status = json["status"] as? String,
                   status.lowercased() == "error" {
                    let errorMsg = json["msg"] as? String ?? "Hello request failed"
                    throw KeyPathError.communication(.connectionFailed(reason: errorMsg))
                }
            }

            let raw = String(data: lastLine, encoding: .utf8) ?? ""
            AppLogger.shared.error("🌐 [TCP] hello parse failed: \(raw)")
            throw KeyPathError.communication(.invalidResponse)
        }
    }

    /// Enforce minimum protocol/capabilities. Callers pass only what they need.
    func enforceMinimumCapabilities(required: [String]) async throws {
        let hello = try await hello()
        guard hello.protocolVersion >= 1, hello.hasCapabilities(required) else {
            AppLogger.shared.error(
                "🌐 [TCP] capability check failed required=\(required.joined(separator: ",")) caps=\(hello.capabilities.joined(separator: ","))"
            )
            throw KeyPathError.communication(.invalidResponse)
        }
        AppLogger.shared.debug(
            "🌐 [TCP] capability check ok required=\(required.joined(separator: ","))")
    }

    /// Fetch StatusInfo
    func getStatus() async throws -> TcpStatusInfo {
        // FIX #3: Wrap operation with error recovery to clean up bad connections
        try await withErrorRecovery {
            let requestId = generateRequestId()
            let requestData = try JSONEncoder().encode(["Status": ["request_id": requestId]])
            let responseData = try await send(requestData)
            if let status = try extractMessage(
                named: "StatusInfo", into: TcpStatusInfo.self, from: responseData
            ) {
                return status
            }
            throw KeyPathError.communication(.invalidResponse)
        }
    }

    /// Request available layer names from Kanata
    func requestLayerNames() async throws -> [String] {
        try await withErrorRecovery {
            let requestId = generateRequestId()
            let requestData = try JSONEncoder().encode(["RequestLayerNames": ["request_id": requestId]])
            let responseData = try await send(requestData)
            if let response = try extractMessage(
                named: "LayerNames", into: TcpLayerNames.self, from: responseData
            ) {
                return response.names
            }
            throw KeyPathError.communication(.invalidResponse)
        }
    }

    /// Check if TCP server is available
    func checkServerStatus() async -> Bool {
        AppLogger.shared.debug("🌐 [TCP] Checking server status for \(host):\(port)")

        do {
            // Use RequestCurrentLayerName as a simple ping
            let pingData = try JSONEncoder().encode(["RequestCurrentLayerName": [:] as [String: String]])
            let responseData = try await send(pingData)

            if let responseString = String(data: responseData, encoding: .utf8) {
                AppLogger.shared.debug("✅ [TCP] Server is responding: \(responseString.prefix(100))")
                return true
            }

            return false
        } catch {
            AppLogger.shared.warn("❌ [TCP] Server check failed: \(error)")
            // FIX #3: Close connection on error so next call gets fresh connection
            if shouldRetry(error) {
                AppLogger.shared.debug("🌐 [TCP] Closing connection after server check failure")
                closeConnection()
            }
            return false
        }
    }

    /// Send reload command to Kanata
    /// Prefer Reload(wait/timeout_ms); fall back to basic {"Reload":{}} and Ok/Error if needed.
    func reloadConfig(timeoutMs: UInt32 = 5000) async -> TCPReloadResult {
        let startTime = Date()
        AppLogger.shared.log("⏱️ [TCP] t=0ms: Starting reload (timeoutMs=\(timeoutMs))")

        do {
            // Preferred: wait contract (v2)
            let requestId = generateRequestId()
            let req: [String: Any] = [
                "Reload": [
                    "wait": true,
                    "timeout_ms": Int(timeoutMs),
                    "request_id": requestId
                ]
            ]
            let requestData = try JSONSerialization.data(withJSONObject: req)

            AppLogger.shared.log("⏱️ [TCP] t=\(Int(Date().timeIntervalSince(startTime) * 1000))ms: Sending reload request")

            // Read first line (status response) with timeout
            let firstLine = try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await self.send(requestData)
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutMs + 1000) * 1_000_000)
                    throw KeyPathError.communication(.timeout)
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            let firstLineStr = String(data: firstLine, encoding: .utf8) ?? ""
            let connectionStateAfterFirstRead = stateString(connection?.state)
            AppLogger.shared.log("⏱️ [TCP] t=\(Int(Date().timeIntervalSince(startTime) * 1000))ms: First line received, connection state=\(connectionStateAfterFirstRead)")
            AppLogger.shared.log("🔄 [TCP] Reload status: \(firstLineStr)")

            // Check if first line indicates error
            if let json = try? JSONSerialization.jsonObject(with: firstLine) as? [String: Any],
               let status = json["status"] as? String,
               status.lowercased() == "error" {
                let errorMsg = json["msg"] as? String ?? "Reload failed"
                AppLogger.shared.log("❌ [TCP] Reload failed: \(errorMsg)")
                return .failure(error: errorMsg, response: firstLineStr)
            }

            // Read second line (ReloadResult) with timeout
            AppLogger.shared.log("⏱️ [TCP] t=\(Int(Date().timeIntervalSince(startTime) * 1000))ms: About to get connection for second line read")
            let connection = try await ensureConnectionCore()
            AppLogger.shared.log("⏱️ [TCP] t=\(Int(Date().timeIntervalSince(startTime) * 1000))ms: Starting second line read, connection state=\(connection.state)")

            let secondLine = try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await self.readUntilNewline(on: connection)
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutMs + 1000) * 1_000_000)
                    throw KeyPathError.communication(.timeout)
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }

            AppLogger.shared.log("⏱️ [TCP] t=\(Int(Date().timeIntervalSince(startTime) * 1000))ms: Second line received, connection state=\(connection.state)")

            if let reload = try extractMessage(
                named: "ReloadResult", into: ReloadResult.self, from: secondLine
            ) {
                if reload.ready {
                    let dur = reload.duration_ms ?? 0
                    let ep = reload.epoch ?? 0
                    let totalTime = Int(Date().timeIntervalSince(startTime) * 1000)
                    AppLogger.shared.log("✅ [TCP] Reload(wait) ok duration=\(dur)ms epoch=\(ep)")
                    AppLogger.shared.log("⏱️ [TCP] t=\(totalTime)ms: Reload completed successfully")
                    let secondLineStr = String(data: secondLine, encoding: .utf8) ?? ""
                    return .success(response: secondLineStr)
                } else {
                    let totalTime = Int(Date().timeIntervalSince(startTime) * 1000)
                    AppLogger.shared.log("⚠️ [TCP] Reload(wait) timeout before \(reload.timeout_ms) ms")
                    AppLogger.shared.log("⏱️ [TCP] t=\(totalTime)ms: Reload timed out")
                    let secondLineStr = String(data: secondLine, encoding: .utf8) ?? ""
                    return .failure(error: "timeout", response: secondLineStr)
                }
            }

            // If we couldn't parse ReloadResult, treat status OK as success (backward compat)
            let totalTime = Int(Date().timeIntervalSince(startTime) * 1000)
            AppLogger.shared.log("✅ [TCP] Config reload acknowledged (status OK, no ReloadResult)")
            AppLogger.shared.log("⏱️ [TCP] t=\(totalTime)ms: Reload completed (backward compat mode)")
            return .success(response: firstLineStr)
        } catch {
            let totalTime = Int(Date().timeIntervalSince(startTime) * 1000)
            let connectionState = stateString(connection?.state)
            AppLogger.shared.log("❌ [TCP] Reload error at t=\(totalTime)ms: \(error)")
            AppLogger.shared.log("❌ [TCP] Connection state at error: \(connectionState)")
            // FIX #3: Close connection on error so next call gets fresh connection
            if shouldRetry(error) {
                AppLogger.shared.debug("🌐 [TCP] Closing connection after reload error")
                closeConnection()
            }
            return .networkError(error.localizedDescription)
        }
    }

    private struct ReloadResult: Codable {
        let ready: Bool
        let timeout_ms: UInt32
        let ok: Bool?
        let duration_ms: UInt64?
        let epoch: UInt64?
        let request_id: UInt64?
    }

    // MARK: - Virtual/Fake Key Actions

    /// Action types for fake key commands
    enum FakeKeyAction: String, Sendable {
        case press = "Press"
        case release = "Release"
        case tap = "Tap"
        case toggle = "Toggle"
    }

    /// Result of acting on a fake key
    enum FakeKeyResult: Sendable {
        case success
        case error(String)
        case networkError(String)
    }

    /// Trigger a virtual/fake key defined in Kanata config via TCP
    ///
    /// This allows external tools (deep links, Raycast, etc.) to trigger
    /// actions defined in `defvirtualkeys` or `deffakekeys`.
    ///
    /// Example Kanata config:
    /// ```
    /// (defvirtualkeys
    ///   email-sig (macro H e l l o spc W o r l d)
    ///   launch-obsidian (cmd open -a Obsidian)
    /// )
    /// ```
    ///
    /// Then trigger via: `keypath://fakekey/email-sig/tap`
    ///
    /// - Parameters:
    ///   - name: The name of the virtual/fake key as defined in config
    ///   - action: The action to perform (press, release, tap, toggle)
    /// - Returns: Result indicating success or failure
    func actOnFakeKey(name: String, action: FakeKeyAction) async -> FakeKeyResult {
        AppLogger.shared.log("🎹 [TCP] ActOnFakeKey: \(name) \(action.rawValue)")

        do {
            let requestId = generateRequestId()
            let req: [String: Any] = [
                "ActOnFakeKey": [
                    "name": name,
                    "action": action.rawValue,
                    "request_id": requestId
                ]
            ]
            let requestData = try JSONSerialization.data(withJSONObject: req)

            let responseData = try await send(requestData)
            let responseStr = String(data: responseData, encoding: .utf8) ?? ""
            AppLogger.shared.log("🎹 [TCP] ActOnFakeKey response: \(responseStr)")

            // Parse response
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let status = json["status"] as? String {
                if status.lowercased() == "ok" {
                    AppLogger.shared.log("✅ [TCP] ActOnFakeKey success: \(name)")
                    return .success
                } else {
                    let errorMsg = json["msg"] as? String ?? "Unknown error"
                    AppLogger.shared.log("❌ [TCP] ActOnFakeKey failed: \(errorMsg)")
                    return .error(errorMsg)
                }
            }

            return .success
        } catch {
            AppLogger.shared.error("❌ [TCP] ActOnFakeKey error: \(error)")
            if shouldRetry(error) {
                closeConnection()
            }
            return .networkError(error.localizedDescription)
        }
    }

    // MARK: - Core Send/Receive

    /// Send TCP message and receive response with timeout
    private func send(_ data: Data) async throws -> Data {
        do {
            return try await sendCore(data)
        } catch {
            if shouldRetry(error) {
                AppLogger.shared.debug("🌐 [TCP] send retry after backoff: \(error)")
                try? await Task.sleep(nanoseconds: UInt64(retryBackoffSeconds * 1_000_000_000))
                closeConnection()
                return try await sendCore(data)
            }
            throw error
        }
    }

    private func sendCore(_ data: Data) async throws -> Data {
        // Ensure connection is ready
        let connection = try await ensureConnectionCore()

        // Send with timeout
        return try await withThrowingTaskGroup(of: Data.self) { group in
            // Main send/receive task
            group.addTask {
                try await self.sendAndReceive(on: connection, data: data)
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
                throw KeyPathError.communication(.timeout)
            }

            // Return first result and cancel other task
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func shouldRetry(_ error: Error) -> Bool {
        if let kpe = error as? KeyPathError {
            switch kpe {
            case .communication(.timeout), .communication(.connectionFailed):
                return true
            default:
                return false
            }
        }
        return false
    }

    /// Read newline-delimited data from connection
    /// Returns exactly ONE complete line (ending with \n) from the connection.
    /// Uses a persistent buffer to handle cases where Kanata sends multiple
    /// lines in a single TCP packet.
    private func readUntilNewline(on connection: NWConnection) async throws -> Data {
        // Validate connection is ready before attempting read
        guard connection.state == .ready else {
            AppLogger.shared.log("❌ [TCP] readUntilNewline called on non-ready connection (state=\(connection.state))")
            throw KeyPathError.communication(.connectionFailed(reason: "Connection not ready: \(connection.state)"))
        }

        let maxLength = 65536

        // Check if we already have a complete line in the buffer
        if let (line, remaining) = extractFirstLine(from: readBuffer) {
            readBuffer = remaining
            AppLogger.shared.debug("🔌 [TCP] Returning buffered line (\(line.count) bytes, \(remaining.count) bytes remaining)")
            return line
        }

        // Thread-safe accumulator for use in NWConnection callback
        final class Accumulator: @unchecked Sendable {
            var data: Data
            init(initial: Data) { data = initial }
        }

        // Start with existing buffer contents
        let accumulator = Accumulator(initial: readBuffer)

        // No complete line in buffer, need to read from connection
        while true {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) {
                    content, _, isComplete, error in
                    if let error {
                        continuation.resume(
                            throwing: KeyPathError.communication(
                                .connectionFailed(reason: error.localizedDescription)))
                        return
                    }

                    if let content {
                        accumulator.data.append(content)
                        // Check if we now have at least one complete line (ending with \n)
                        if accumulator.data.contains(0x0A) {
                            continuation.resume()
                            return
                        }
                    }

                    if isComplete {
                        // Connection closed - return what we have if we have data, otherwise error
                        if accumulator.data.isEmpty {
                            continuation.resume(
                                throwing: KeyPathError.communication(.connectionFailed(reason: "Connection closed"))
                            )
                        } else {
                            // Return partial data if connection closed (may be valid for last line)
                            continuation.resume()
                        }
                        return
                    }

                    // No data yet, continue reading
                    continuation.resume()
                }
            }

            // Check if we have a complete line now
            if let (line, remaining) = extractFirstLine(from: accumulator.data) {
                // Store remaining data back in the persistent buffer
                readBuffer = remaining
                AppLogger.shared.debug("🔌 [TCP] Returning line (\(line.count) bytes, \(remaining.count) bytes remaining in buffer)")
                return line
            }

            // If we've accumulated too much without a newline, something is wrong
            if accumulator.data.count >= maxLength {
                throw KeyPathError.communication(
                    .connectionFailed(reason: "Response too large or malformed"))
            }
        }
    }

    /// Extract the first complete line (up to and including \n) from data.
    /// Returns the line and the remaining data, or nil if no complete line exists.
    /// Internal visibility for unit testing.
    nonisolated func extractFirstLine(from data: Data) -> (line: Data, remaining: Data)? {
        guard let newlineIndex = data.firstIndex(of: 0x0A) else {
            return nil
        }
        let lineEndIndex = data.index(after: newlineIndex)
        let line = Data(data.prefix(upTo: lineEndIndex))
        let remaining = Data(data.suffix(from: lineEndIndex))
        return (line, remaining)
    }

    /// Check if a JSON message is an unsolicited broadcast event (not a command response)
    private nonisolated func isUnsolicitedBroadcast(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        // These are broadcast events that Kanata sends to all clients
        let broadcastKeys = ["LayerChange", "ConfigFileReload", "MessagePush", "Ready", "ConfigError"]
        return broadcastKeys.contains(where: { json[$0] != nil })
    }

    /// Helper to extract request_id from a JSON response
    private nonisolated func extractRequestId(from data: Data) -> UInt64? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        func parseRequestIdValue(_ value: Any) -> UInt64? {
            if let number = value as? NSNumber {
                return number.uint64Value
            }
            if let stringValue = value as? String, let parsed = UInt64(stringValue) {
                return parsed
            }
            return value as? UInt64
        }

        if let topLevel = json["request_id"], let id = parseRequestIdValue(topLevel) {
            return id
        }

        // Try to find request_id in the first level of any message type
        for (_, value) in json {
            if let dict = value as? [String: Any],
               let nested = dict["request_id"],
               let requestId = parseRequestIdValue(nested) {
                return requestId
            }
        }

        return nil
    }

    #if DEBUG
        /// Test hook exposed in DEBUG builds to validate request_id parsing behavior.
        nonisolated func _testExtractRequestId(from data: Data) -> UInt64? {
            extractRequestId(from: data)
        }
    #endif

    /// Core TCP send/receive implementation with request_id matching
    /// Falls back to broadcast draining if server doesn't support request_id
    private func sendAndReceive(on connection: NWConnection, data: Data) async throws -> Data {
        // Extract request_id from the outgoing message (if present)
        let sentRequestId = extractRequestId(from: data)

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Data, Error>) in
            let completionFlag = CompletionFlag()

            // Send data
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        if completionFlag.markCompleted() {
                            continuation.resume(
                                throwing: KeyPathError.communication(
                                    .connectionFailed(reason: error.localizedDescription)))
                        }
                        return
                    }

                    // Read response, using request_id matching if available
                    Task {
                        do {
                            var responseData: Data
                            var attempts = 0
                            let maxDrainAttempts = 50 // Prevent infinite loop - increased for high load scenarios

                            // If we sent a request_id, match responses by request_id
                            // Otherwise fall back to old broadcast draining behavior
                            repeat {
                                responseData = try await withTimeout(seconds: 5.0) {
                                    try await self.readUntilNewline(on: connection)
                                }
                                attempts += 1

                                // First check: is this an unsolicited broadcast?
                                if self.isUnsolicitedBroadcast(responseData) {
                                    if let msgStr = String(data: responseData, encoding: .utf8) {
                                        AppLogger.shared.log("🔄 [TCP] Skipping broadcast: \(msgStr.prefix(100))")
                                    }
                                    continue // Read next line
                                }

                                // Second check: if we sent request_id, verify it matches
                                if let sentId = sentRequestId {
                                    if let responseId = self.extractRequestId(from: responseData) {
                                        if responseId == sentId {
                                            // Perfect match - this is our response
                                            AppLogger.shared.debug("✅ [TCP] Matched response by request_id=\(sentId)")
                                            break
                                        } else {
                                            // Response has request_id but it doesn't match - skip it
                                            if let msgStr = String(data: responseData, encoding: .utf8) {
                                                AppLogger.shared.log(
                                                    "🔄 [TCP] Skipping mismatched response (expected=\(sentId), got=\(responseId)): \(msgStr.prefix(100))"
                                                )
                                            }
                                            continue
                                        }
                                    } else {
                                        // We sent request_id but response doesn't have one
                                        // This is likely a broadcast that slipped through - skip it
                                        // Modern Kanata versions support request_id, so rejecting is safer
                                        if let msgStr = String(data: responseData, encoding: .utf8) {
                                            AppLogger.shared.warn(
                                                "⚠️ [TCP] Response missing request_id when we sent \(sentId) - likely broadcast, skipping: \(msgStr.prefix(100))"
                                            )
                                        }
                                        continue // Skip and read next line
                                    }
                                }

                                // No request_id matching - got a response that's not a broadcast
                                break
                            } while attempts < maxDrainAttempts

                            if attempts >= maxDrainAttempts {
                                throw KeyPathError.communication(.invalidResponse)
                            }

                            if completionFlag.markCompleted() {
                                continuation.resume(returning: responseData)
                            }
                        } catch {
                            if completionFlag.markCompleted() {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
            )
        }
    }

    /// Extract error message from JSON response using structured parsing
    private func extractError(from response: String) -> String {
        // Try to parse as ServerResponse first
        if let data = response.data(using: .utf8) {
            // Check if it's a single-line response
            let lines = response.split(separator: "\n")
            if let firstLine = lines.first,
               let lineData = String(firstLine).data(using: .utf8) {
                if let serverResponse = try? JSONDecoder().decode(TcpServerResponse.self, from: lineData),
                   serverResponse.isError {
                    return serverResponse.msg ?? "Unknown error"
                }
            }

            // Fallback: try parsing as generic JSON
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let error = json["error"] as? String {
                    return error
                }
                if let msg = json["msg"] as? String {
                    return msg
                }
            }
        }
        return "Unknown error"
    }

    /// Extract a named server message (second line) from a newline-delimited response
    private func extractMessage<T: Decodable>(named name: String, into _: T.Type, from data: Data)
        throws -> T? {
        guard let s = String(data: data, encoding: .utf8) else {
            AppLogger.shared.log("🔍 [TCP extractMessage] Failed to decode data as UTF-8")
            return nil
        }

        AppLogger.shared.log(
            "🔍 [TCP extractMessage] Looking for '\(name)' in response: \(s.prefix(200))")

        // Split by newlines; look for an object where the top-level key is the provided name
        for (index, line) in s.split(separator: "\n").map(String.init).enumerated() {
            AppLogger.shared.log("🔍 [TCP extractMessage] Line \(index): \(line.prefix(150))")

            guard let lineData = line.data(using: .utf8) else { continue }
            // Try loose parse via JSONSerialization to locate the named object
            guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                AppLogger.shared.log("🔍 [TCP extractMessage] Line \(index): Not valid JSON object")
                continue
            }

            AppLogger.shared.log(
                "🔍 [TCP extractMessage] Line \(index) keys: \(obj.keys.joined(separator: ", "))")

            guard let payload = obj[name] else {
                AppLogger.shared.log("🔍 [TCP extractMessage] Line \(index): Missing key '\(name)'")
                continue
            }

            // Re-encode payload and decode strongly
            guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
                AppLogger.shared.log("🔍 [TCP extractMessage] Line \(index): Failed to re-encode payload")
                continue
            }

            do {
                let decoded = try JSONDecoder().decode(T.self, from: payloadData)
                AppLogger.shared.log(
                    "✅ [TCP extractMessage] Successfully decoded '\(name)' from line \(index)")
                return decoded
            } catch {
                AppLogger.shared.log("❌ [TCP extractMessage] Line \(index): Decoding failed: \(error)")
                continue
            }
        }

        AppLogger.shared.log("❌ [TCP extractMessage] Could not find '\(name)' in any line")
        return nil
    }
}

// MARK: - Result Types

enum TCPReloadResult {
    case success(response: String)
    case failure(error: String, response: String)
    case networkError(String)

    var isSuccess: Bool {
        switch self {
        case .success:
            true
        default:
            false
        }
    }

    var errorMessage: String? {
        switch self {
        case let .failure(error, _):
            error
        case let .networkError(error):
            error
        case .success:
            nil
        }
    }

    var response: String? {
        switch self {
        case let .success(response):
            response
        case let .failure(_, response):
            response
        case .networkError:
            nil
        }
    }

    var isCancellation: Bool {
        guard let message = errorMessage else { return false }
        return message.contains("CancellationError") || message.localizedCaseInsensitiveContains("cancel")
    }
}

// MARK: - Timeout Helper

/// Execute an async operation with a timeout
private func withTimeout<T: Sendable>(
    seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Add the actual operation
        group.addTask {
            try await operation()
        }

        // Add a timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }

        // Wait for the first one to complete
        guard let result = try await group.next() else {
            throw TimeoutError()
        }

        // Cancel the other task
        group.cancelAll()

        return result
    }
}

/// Error thrown when an operation times out
private struct TimeoutError: Error, LocalizedError {
    var errorDescription: String? {
        "Operation timed out"
    }
}
