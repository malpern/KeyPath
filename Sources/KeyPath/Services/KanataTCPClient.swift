import Foundation
import Network
import KeyPathCore

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
            let serverString = (try container.decodeIfPresent(String.self, forKey: .server)) ?? "kanata"
            let caps = (try container.decodeIfPresent([String].self, forKey: .capabilities)) ?? []
            self.version = serverString
            self.protocolVersion = 1
            self.capabilities = caps
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

    /// Validate configuration (currently not supported by kanata TCP server)
    func validateConfig(_ configContent: String) async -> TCPValidationResult {
        AppLogger.shared.debug("📝 [TCP] Config validation requested (\(configContent.count) bytes)")
        AppLogger.shared.debug("📝 [TCP] Note: ValidateConfig not supported by kanata - will validate on file load")
        return .success
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

            // Fallback: Ok/Error contract
            let responseString = String(data: responseData, encoding: .utf8) ?? ""
            if responseString.contains("\"status\":\"Ok\"") || responseString.contains("Live reload successful") {
                AppLogger.shared.log("✅ [TCP] Config reload successful (fallback)")
                return .success(response: responseString)
            } else if responseString.contains("\"status\":\"Error\"") {
                let error = extractError(from: responseString)
                return .failure(error: error, response: responseString)
            } else if responseString.contains("AuthRequired") {
                return .authenticationRequired
            }

            return .failure(error: "Unexpected response format", response: String(data: responseData, encoding: .utf8) ?? "")
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

            if let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let status = json["status"] as? String, status == "Ok" {
                AppLogger.shared.log("✅ [TCP] Kanata restart request sent")
                return true
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
        // Ensure connection is ready
        let connection = try await ensureConnection()

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

    /// Core TCP send/receive implementation
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

                // Receive response (TCP streams data, so we need to handle framing)
                // Kanata sends multiple newline-delimited JSON objects
                // Wait a bit to accumulate all responses before reading
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
                        if completionFlag.markCompleted() {
                            if let error {
                                continuation.resume(throwing: KeyPathError.communication(.connectionFailed(reason: error.localizedDescription)))
                            } else if let content {
                                continuation.resume(returning: content)
                            } else if isComplete {
                                continuation.resume(throwing: KeyPathError.communication(.connectionFailed(reason: "Connection closed")))
                            } else {
                                continuation.resume(throwing: KeyPathError.communication(.connectionFailed(reason: "Empty response")))
                            }
                        }
                    }
                }
            })
        }
    }

    /// Extract error message from JSON response
    private func extractError(from response: String) -> String {
        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? String {
            return error
        }
        return "Unknown error"
    }

    /// Extract a named server message (second line) from a newline-delimited response
    private func extractMessage<T: Decodable>(named name: String, into type: T.Type, from data: Data) throws -> T? {
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
