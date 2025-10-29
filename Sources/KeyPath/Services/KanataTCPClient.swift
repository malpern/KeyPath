import Foundation
import Network

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
/// - Keep authentication (required by kanata protocol)
/// - Connection pooling for efficiency
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
        AppLogger.shared.log("🔐 [TCP] Authenticating as '\(clientName)'")

        do {
            let request = TCPAuthRequest(token: token, client_name: clientName)
            let requestData = try JSONEncoder().encode(["Authenticate": request])
            let responseData = try await send(requestData)

            // Parse authentication response
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let authResponseDict = json["Authenticated"] as? [String: Any],
               let success = authResponseDict["success"] as? Bool,
               let sessionId = authResponseDict["session_id"] as? String
            {
                if success {
                    authToken = token
                    self.sessionId = sessionId
                    AppLogger.shared.log("✅ [TCP] Authentication successful, session: \(sessionId)")
                    return true
                }
            }

            AppLogger.shared.log("❌ [TCP] Authentication failed")
            return false
        } catch {
            AppLogger.shared.log("❌ [TCP] Authentication error: \(error)")
            return false
        }
    }

    /// Clear authentication state
    func clearAuthentication() {
        authToken = nil
        sessionId = nil
        AppLogger.shared.log("🧹 [TCP] Authentication cleared")
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
        AppLogger.shared.log("🔌 [TCP] Closing connection")
        closeConnection()
        clearAuthentication()
    }

    // MARK: - Server Operations

    /// Check if TCP server is available
    func checkServerStatus(authToken: String? = nil) async -> Bool {
        AppLogger.shared.log("🌐 [TCP] Checking server status for \(host):\(port)")

        do {
            // Use RequestCurrentLayerName as a simple ping
            let pingData = try JSONEncoder().encode(["RequestCurrentLayerName": [:] as [String: String]])
            let responseData = try await send(pingData)

            if let responseString = String(data: responseData, encoding: .utf8) {
                AppLogger.shared.log("✅ [TCP] Server is responding: \(responseString.prefix(100))")

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
            AppLogger.shared.log("❌ [TCP] Server check failed: \(error)")
            return false
        }
    }

    /// Validate configuration (currently not supported by kanata TCP server)
    func validateConfig(_ configContent: String) async -> TCPValidationResult {
        AppLogger.shared.log("📝 [TCP] Config validation requested (\(configContent.count) bytes)")
        AppLogger.shared.log("📝 [TCP] Note: ValidateConfig not supported by kanata - will validate on file load")
        return .success
    }

    /// Send reload command to Kanata
    func reloadConfig() async -> TCPReloadResult {
        guard isAuthenticated, let sessionId else {
            AppLogger.shared.log("❌ [TCP] Not authenticated for config reload")
            return .authenticationRequired
        }

        AppLogger.shared.log("🔄 [TCP] Triggering config reload")

        do {
            let request = TCPReloadRequest(session_id: sessionId)
            let requestData = try JSONEncoder().encode(["Reload": request])
            let responseData = try await send(requestData)

            let responseString = String(data: responseData, encoding: .utf8) ?? ""
            AppLogger.shared.log("🌐 [TCP] Reload response: \(responseString)")

            if responseString.contains("\"status\":\"Ok\"") || responseString.contains("Live reload successful") {
                AppLogger.shared.log("✅ [TCP] Config reload successful")
                return .success(response: responseString)
            } else if responseString.contains("\"status\":\"Error\"") {
                let error = extractError(from: responseString)
                AppLogger.shared.log("❌ [TCP] Config reload failed: \(error)")
                return .failure(error: error, response: responseString)
            } else if responseString.contains("AuthRequired") {
                return .authenticationRequired
            }

            AppLogger.shared.log("⚠️ [TCP] Unexpected reload response")
            return .failure(error: "Unexpected response format", response: responseString)
        } catch {
            AppLogger.shared.log("❌ [TCP] Reload error: \(error)")
            return .networkError(error.localizedDescription)
        }
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
               let status = json["status"] as? String, status == "Ok"
            {
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
                // Kanata sends newline-delimited JSON, read until newline
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
            })
        }
    }

    /// Extract error message from JSON response
    private func extractError(from response: String) -> String {
        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? String
        {
            return error
        }
        return "Unknown error"
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
    case failure(errors: [ConfigValidationError])
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
