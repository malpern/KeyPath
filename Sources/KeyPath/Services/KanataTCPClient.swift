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

    // Simple authentication state
    private var authToken: String?
    private var sessionId: String?

    // Handshake cache
    private var cachedHello: TcpHelloOk?

    // MARK: - Initialization

    init(host: String = "127.0.0.1", port: Int, timeout: TimeInterval = 5.0, reuseConnection _: Bool = true) {
        self.host = host
        self.port = port
        self.timeout = timeout
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
            return connection
        }

        // Wait if already connecting
        while isConnecting {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        // Check again after waiting
        if let connection, connection.state == .ready {
            return connection
        }

        // Create new connection
        isConnecting = true
        defer { isConnecting = false }

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
                        switch state {
                        case .ready:
                            if completionFlag.markCompleted() {
                                continuation.resume(returning: newConnection)
                            }

                        case let .failed(error):
                            if completionFlag.markCompleted() {
                                continuation.resume(throwing: KeyPathError.communication(.connectionFailed(reason: error.localizedDescription)))
                            }
                            newConnection.cancel()

                        case .cancelled:
                            if completionFlag.markCompleted() {
                                continuation.resume(throwing: KeyPathError.communication(.connectionFailed(reason: "Connection cancelled")))
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
            return result
        }
    }

    private func closeConnection() {
        connection?.cancel()
        connection = nil
    }

    // MARK: - Authentication

    private var isAuthenticated: Bool {
        authToken != nil && sessionId != nil
    }

    /// Authenticate with the Kanata TCP server
    func authenticate(token: String, clientName: String = "KeyPath") async -> Bool {
        AppLogger.shared.debug("🔐 [TCP] Authenticating as '\(clientName)'")

        do {
            let request = TCPAuthRequest(token: token, client_name: clientName)
            let requestData = try JSONEncoder().encode(["Authenticate": request])
            let responseData = try await send(requestData)

            // Parse authentication response
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let authResponseDict = json["Authenticated"] as? [String: Any],
               let success = authResponseDict["success"] as? Bool,
               let sessionId = authResponseDict["session_id"] as? String {
                if success {
                    authToken = token
                    self.sessionId = sessionId
                    AppLogger.shared.info("✅ [TCP] Authentication successful, session: \(sessionId)")
                    return true
                }
            }

            AppLogger.shared.warn("❌ [TCP] Authentication failed")
            return false
        } catch {
            AppLogger.shared.error("❌ [TCP] Authentication error: \(error)")
            return false
        }
    }

    /// Clear authentication state
    func clearAuthentication() {
        authToken = nil
        sessionId = nil
        AppLogger.shared.debug("🧹 [TCP] Authentication cleared")
    }

    /// Check if authenticated, try to restore from shared token if not
    func ensureAuthenticated() async -> Bool {
        if isAuthenticated {
            return true
        }

        // Try to authenticate using shared token from keychain
        let token = try? await MainActor.run { try KeychainService.shared.retrieveTCPToken() }
        if let token, !token.isEmpty {
            return await authenticate(token: token)
        }

        return false
    }

    /// Cancel any ongoing operations and close connection
    func cancelInflightAndCloseConnection() {
        AppLogger.shared.debug("🔌 [TCP] Closing connection")
        closeConnection()
        clearAuthentication()
    }

    // MARK: - Server Operations

    // MARK: - Protocol Models

    struct TcpHelloOk: Codable, Sendable {
        let version: String
        let protocolVersion: Int
        let capabilities: [String]

        enum CodingKeys: String, CodingKey {
            case version
            case protocolVersion = "protocol"
            case capabilities
            // Minimal server compatibility
            case server
        }

        init(version: String, protocolVersion: Int, capabilities: [String]) {
            self.version = version
            self.protocolVersion = protocolVersion
            self.capabilities = capabilities
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
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
    }

    struct TcpValidationItem: Codable, Sendable {
        let code: String
        let message: String
        let line: UInt32?
        let column: UInt32?
    }

    struct TcpValidationResult: Codable, Sendable {
        let warnings: [TcpValidationItem]
        let errors: [TcpValidationItem]
    }

    // MARK: - Handshake / Status

    /// Perform Hello handshake and cache capabilities
    func hello() async throws -> TcpHelloOk {
        if let cachedHello { return cachedHello }

        let requestData = try JSONEncoder().encode(["Hello": [:] as [String: String]])
        let start = CFAbsoluteTimeGetCurrent()
        let responseData = try await send(requestData)
        let dt = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        if let raw = String(data: responseData, encoding: .utf8) {
            AppLogger.shared.debug("🌐 [TCP] hello response bytes=\(responseData.count) duration_ms=\(dt) sample=\(raw.prefix(120))")
        } else {
            AppLogger.shared.debug("🌐 [TCP] hello response bytes=\(responseData.count) duration_ms=\(dt)")
        }
        guard let hello = try extractMessage(named: "HelloOk", into: TcpHelloOk.self, from: responseData) else {
            AppLogger.shared.error("🌐 [TCP] hello parse failed")
            throw KeyPathError.communication(.invalidResponse)
        }
        AppLogger.shared.debug("🌐 [TCP] hello ok protocol=\(hello.protocolVersion) caps=\(hello.capabilities.joined(separator: ","))")
        cachedHello = hello
        return hello
    }

    /// Enforce minimum protocol/capabilities. Callers pass only what they need.
    func enforceMinimumCapabilities(required: [String]) async throws {
        let hello = try await hello()
        guard hello.protocolVersion >= 1, hello.hasCapabilities(required) else {
            AppLogger.shared.error("🌐 [TCP] capability check failed required=\(required.joined(separator: ",")) caps=\(hello.capabilities.joined(separator: ","))")
            throw KeyPathError.communication(.invalidResponse)
        }
        AppLogger.shared.debug("🌐 [TCP] capability check ok required=\(required.joined(separator: ","))")
    }

    /// Fetch StatusInfo
    func getStatus() async throws -> TcpStatusInfo {
        let requestData = try JSONEncoder().encode(["Status": [:] as [String: String]])
        let responseData = try await send(requestData)
        if let status = try extractMessage(named: "StatusInfo", into: TcpStatusInfo.self, from: responseData) {
            return status
        }
        throw KeyPathError.communication(.invalidResponse)
    }

    /// Check if TCP server is available
    func checkServerStatus(authToken: String? = nil) async -> Bool {
        AppLogger.shared.debug("🌐 [TCP] Checking server status for \(host):\(port)")

        do {
            // Use RequestCurrentLayerName as a simple ping
            let pingData = try JSONEncoder().encode(["RequestCurrentLayerName": [:] as [String: String]])
            let responseData = try await send(pingData)

            if let responseString = String(data: responseData, encoding: .utf8) {
                AppLogger.shared.debug("✅ [TCP] Server is responding: \(responseString.prefix(100))")

                // Try authentication if token provided
                let token: String? = if let provided = authToken {
                    provided
                } else {
                    try? await MainActor.run { try KeychainService.shared.retrieveTCPToken() }
                }

                if let token, !token.isEmpty {
                    return await authenticate(token: token)
                }

                return true
            }

            return false
        } catch {
            AppLogger.shared.warn("❌ [TCP] Server check failed: \(error)")
            return false
        }
    }

    /// Validate configuration via TCP (Phase 2)
    /// Note: Kanata's Validate command returns TWO lines:
    ///   Line 1: {"status":"Ok"} - acknowledges command received
    ///   Line 2: {"ValidationResult": {...}} - validation details
    func validateConfig(_ configContent: String) async -> TCPValidationResult {
        AppLogger.shared.debug("📝 [TCP] Config validation requested (\(configContent.count) bytes)")
        do {
            // Ensure capability or proceed best-effort
            _ = try? await enforceMinimumCapabilities(required: ["validate"]) // soft-check

            let payload: [String: Any] = [
                "Validate": [
                    "config": configContent
                ]
            ]
            let requestData = try JSONSerialization.data(withJSONObject: payload)

            // Read first line (status response)
            let firstLine = try await send(requestData)
            let firstLineStr = String(data: firstLine, encoding: .utf8) ?? ""
            AppLogger.shared.debug("📝 [TCP] Validation status: \(firstLineStr)")

            // Check if first line indicates error
            if let json = try? JSONSerialization.jsonObject(with: firstLine) as? [String: Any],
               let status = json["status"] as? String,
               status.lowercased() == "error" {
                let errorMsg = json["msg"] as? String ?? "Validation request failed"
                return .failure(errors: [errorMsg])
            }

            // Read second line (ValidationResult)
            let connection = try await ensureConnectionCore()
            let secondLine = try await readUntilNewline(on: connection)
            AppLogger.shared.debug("📝 [TCP] Validation result received (\(secondLine.count) bytes)")

            // Parse ValidationResult from second line
            if let vr = try extractMessage(named: "ValidationResult", into: TcpValidationResult.self, from: secondLine) {
                if vr.errors.isEmpty {
                    AppLogger.shared.info("✅ [TCP] Validation succeeded")
                    return .success
                } else {
                    let msgs = vr.errors.map { item in
                        var ctx = item.message
                        if let line = item.line { ctx += " (line \(line))" }
                        return ctx
                    }
                    AppLogger.shared.warn("⚠️ [TCP] Validation failed with \(msgs.count) error(s)")
                    return .failure(errors: msgs)
                }
            }

            let raw = String(data: secondLine, encoding: .utf8) ?? ""
            AppLogger.shared.error("❌ [TCP] Unexpected validation result format: \(raw)")
            return .failure(errors: ["Unexpected validation result format: \(raw)"])
        } catch {
            AppLogger.shared.error("❌ [TCP] Validate error: \(error)")
            return .networkError(error.localizedDescription)
        }
    }

    /// Subscribe to server events (Ready/ConfigError). Returns true on ack.
    func subscribeToEvents() async -> Bool {
        AppLogger.shared.debug("📡 [TCP] Subscribing to events")
        do {
            _ = try? await enforceMinimumCapabilities(required: ["subscribe"]) // soft-check
            let payload: [String: Any] = [
                "Subscribe": [
                    "events": ["reload", "ready"]
                ]
            ]
            let requestData = try JSONSerialization.data(withJSONObject: payload)
            let responseData = try await send(requestData)

            // Parse response using structured ServerResponse
            if let responseString = String(data: responseData, encoding: .utf8) {
                let lines = responseString.split(separator: "\n")
                if let firstLine = lines.first,
                   let lineData = String(firstLine).data(using: .utf8),
                   let serverResponse = try? JSONDecoder().decode(TcpServerResponse.self, from: lineData),
                   serverResponse.isOk {
                    return true
                }
            }
            return false
        } catch {
            AppLogger.shared.error("❌ [TCP] Subscribe error: \(error)")
            return false
        }
    }

    /// Subscribe on a fresh connection and await one Ready/ConfigError event.
    /// Returns parsed details or nil on timeout/error.
    func awaitOneReloadEvent(timeout: TimeInterval = 3.0) async -> (isReady: Bool, message: String?, line: UInt32?, column: UInt32?)? {
        do {
            let conn = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: UInt16(port)),
                using: .tcp
            )
            return try await withCheckedThrowingContinuation { continuation in
                let completionFlag = CompletionFlag()

                conn.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        let payload = Data("{\"Subscribe\":{\"events\":[\"reload\",\"ready\"]}}\n".utf8)
                        conn.send(content: payload, completion: .contentProcessed { _ in
                            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, _, error in
                                if completionFlag.markCompleted() {
                                    if let error { continuation.resume(throwing: error); return }
                                    guard let content, let s = String(data: content, encoding: .utf8) else {
                                        continuation.resume(returning: nil); return
                                    }
                                    // Parse first line
                                    let first = s.split(separator: "\n").map(String.init).first ?? ""
                                    if let data = first.data(using: .utf8),
                                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                        if (obj["Ready"] as? [String: Any]) != nil {
                                            conn.cancel(); continuation.resume(returning: (true, nil, nil, nil)); return
                                        } else if let err = obj["ConfigError"] as? [String: Any] {
                                            let msg = err["message"] as? String
                                            let line = (err["line"] as? NSNumber)?.uint32Value
                                            let col = (err["column"] as? NSNumber)?.uint32Value
                                            conn.cancel(); continuation.resume(returning: (false, msg, line, col)); return
                                        }
                                    }
                                    conn.cancel(); continuation.resume(returning: nil)
                                }
                            }
                        })
                    case let .failed(error):
                        if completionFlag.markCompleted() { continuation.resume(throwing: error) }
                        conn.cancel()
                    case .cancelled:
                        if completionFlag.markCompleted() { continuation.resume(returning: nil) }
                    default:
                        break
                    }
                }
                conn.start(queue: .global())
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if completionFlag.markCompleted() { conn.cancel(); continuation.resume(returning: nil) }
                }
            }
        } catch {
            AppLogger.shared.warn("❌ [TCP] awaitOneReloadEvent error: \(error)")
            return nil
        }
    }

    /// Send reload command to Kanata
    /// Prefer Reload(wait/timeout_ms); fall back to basic {"Reload":{}} and Ok/Error if needed.
    func reloadConfig(timeoutMs: UInt32 = 5000) async -> TCPReloadResult {
        AppLogger.shared.log("🔄 [TCP] Triggering config reload (timeoutMs=\(timeoutMs))")

        do {
            // Preferred: wait contract (v2)
            let req: [String: Any] = [
                "Reload": [
                    "wait": true,
                    "timeout_ms": Int(timeoutMs)
                ]
            ]
            let requestData = try JSONSerialization.data(withJSONObject: req)
            let responseData = try await send(requestData)

            if let reload = try extractMessage(named: "ReloadResult", into: ReloadResult.self, from: responseData) {
                if reload.ready {
                    let dur = reload.duration_ms ?? 0
                    let ep = reload.epoch ?? 0
                    AppLogger.shared.log("✅ [TCP] Reload(wait) ok duration=\(dur)ms epoch=\(ep)")
                    return .success(response: String(data: responseData, encoding: .utf8) ?? "")
                } else {
                    AppLogger.shared.log("⚠️ [TCP] Reload(wait) timeout before \(reload.timeout_ms) ms")
                    return .failure(error: "timeout", response: String(data: responseData, encoding: .utf8) ?? "")
                }
            }

            // Fallback: Ok/Error contract - parse using structured ServerResponse
            let responseString = String(data: responseData, encoding: .utf8) ?? ""
            let lines = responseString.split(separator: "\n")

            // Try to parse first line as ServerResponse
            if let firstLine = lines.first,
               let lineData = String(firstLine).data(using: .utf8),
               let serverResponse = try? JSONDecoder().decode(TcpServerResponse.self, from: lineData) {
                if serverResponse.isOk {
                    AppLogger.shared.log("✅ [TCP] Config reload successful (fallback)")
                    return .success(response: responseString)
                } else if serverResponse.isError {
                    let errorMsg = serverResponse.msg ?? "Unknown error"
                    AppLogger.shared.log("❌ [TCP] Config reload failed: \(errorMsg)")
                    return .failure(error: errorMsg, response: responseString)
                }
            }

            // Check for AuthRequired message
            if responseString.contains("AuthRequired") {
                return .authenticationRequired
            }

            // Legacy fallback: check for "Live reload successful" string (for very old servers)
            if responseString.contains("Live reload successful") {
                AppLogger.shared.log("✅ [TCP] Config reload successful (legacy fallback)")
                return .success(response: responseString)
            }

            return .failure(error: "Unexpected response format", response: responseString)
        } catch {
            AppLogger.shared.log("❌ [TCP] Reload error: \(error)")
            return .networkError(error.localizedDescription)
        }
    }

    private struct ReloadResult: Codable {
        let ready: Bool
        let timeout_ms: UInt32
        let ok: Bool?
        let duration_ms: UInt64?
        let epoch: UInt64?
    }

    /// Restart Kanata process
    func restartKanata() async -> Bool {
        guard isAuthenticated, let sessionId else {
            AppLogger.shared.log("❌ [TCP] Not authenticated for restart")
            return false
        }

        AppLogger.shared.log("🔄 [TCP] Requesting Kanata restart")

        do {
            let request = TCPRestartRequest(session_id: sessionId)
            let requestData = try JSONEncoder().encode(["Restart": request])
            let responseData = try await send(requestData)

            // Parse response using structured ServerResponse
            if let responseString = String(data: responseData, encoding: .utf8) {
                let lines = responseString.split(separator: "\n")
                if let firstLine = lines.first,
                   let lineData = String(firstLine).data(using: .utf8),
                   let serverResponse = try? JSONDecoder().decode(TcpServerResponse.self, from: lineData),
                   serverResponse.isOk {
                    AppLogger.shared.log("✅ [TCP] Kanata restart request sent")
                    return true
                }
            }

            AppLogger.shared.log("❌ [TCP] Unexpected restart response")
            return false
        } catch {
            AppLogger.shared.log("❌ [TCP] Restart failed: \(error)")
            return false
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
    /// Accumulates data until we have at least one complete line (ending with \n)
    private func readUntilNewline(on connection: NWConnection) async throws -> Data {
        final class Accumulator: @unchecked Sendable {
            var data = Data()
        }

        let accumulator = Accumulator()
        let maxLength = 65536

        while true {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) { content, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: KeyPathError.communication(.connectionFailed(reason: error.localizedDescription)))
                        return
                    }

                    if let content {
                        accumulator.data.append(content)
                        // Check if we have at least one complete line (ending with \n)
                        if accumulator.data.contains(0x0A) { // 0x0A is \n
                            continuation.resume()
                            return
                        }
                    }

                    if isComplete {
                        // Connection closed - return what we have if we have data, otherwise error
                        if accumulator.data.isEmpty {
                            continuation.resume(throwing: KeyPathError.communication(.connectionFailed(reason: "Connection closed")))
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

            // Check if we have complete line(s) now
            if accumulator.data.contains(0x0A) {
                break
            }

            // If we've accumulated too much without a newline, something is wrong
            if accumulator.data.count >= maxLength {
                throw KeyPathError.communication(.connectionFailed(reason: "Response too large or malformed"))
            }
        }

        return accumulator.data
    }

    /// Core TCP send/receive implementation
    /// Properly handles newline-delimited JSON responses without arbitrary delays
    private func sendAndReceive(on connection: NWConnection, data: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let completionFlag = CompletionFlag()

            // Send data
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    if completionFlag.markCompleted() {
                        continuation.resume(throwing: KeyPathError.communication(.connectionFailed(reason: error.localizedDescription)))
                    }
                    return
                }

                // Read response using proper newline-delimited framing
                Task {
                    do {
                        let responseData = try await self.readUntilNewline(on: connection)
                        if completionFlag.markCompleted() {
                            continuation.resume(returning: responseData)
                        }
                    } catch {
                        if completionFlag.markCompleted() {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            })
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
    private func extractMessage<T: Decodable>(named name: String, into _: T.Type, from data: Data) throws -> T? {
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        // Split by newlines; look for an object where the top-level key is the provided name
        for line in s.split(separator: "\n").map(String.init) {
            guard let lineData = line.data(using: .utf8) else { continue }
            // Try loose parse via JSONSerialization to locate the named object
            if let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
               let payload = obj[name] {
                // Re-encode payload and decode strongly
                if let payloadData = try? JSONSerialization.data(withJSONObject: payload) {
                    if let decoded = try? JSONDecoder().decode(T.self, from: payloadData) {
                        return decoded
                    }
                }
            }
        }
        return nil
    }
}

// MARK: - Request/Response Structures

private struct TCPAuthRequest: Codable {
    let token: String
    let client_name: String
}

private struct TCPRestartRequest: Codable {
    let session_id: String
}

private struct TCPReloadRequest: Codable {
    let session_id: String
}

// MARK: - Result Types

enum TCPValidationResult {
    case success
    case failure(errors: [String])
    case authenticationRequired
    case networkError(String)
}

enum TCPReloadResult {
    case success(response: String)
    case failure(error: String, response: String)
    case authenticationRequired
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
        case .authenticationRequired:
            "Authentication required"
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
        default:
            nil
        }
    }
}
