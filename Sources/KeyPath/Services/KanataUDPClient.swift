import Foundation
import Network

/// Simplified UDP client for communicating with Kanata's local UDP server
///
/// Design principles:
/// - Localhost IPC, not distributed networking
/// - Create fresh connections (UDP is connectionless, localhost is instant)
/// - Simple timeout mechanism
/// - Keep authentication (required by kanata protocol)
/// - No connection pooling, session management, or inflight tracking complexity
actor KanataUDPClient {
    private let host: String
    private let port: Int
    private let timeout: TimeInterval

    // Simple authentication state
    private var authToken: String?
    private var sessionId: String?

    // Size limits for UDP reliability
    static let maxUDPPayloadSize = 1200 // Safe MTU size

    // MARK: - Initialization

    init(host: String = "127.0.0.1", port: Int, timeout: TimeInterval = 5.0, reuseConnection: Bool = true) {
        self.host = host
        self.port = port
        self.timeout = timeout
        // reuseConnection parameter kept for API compatibility but ignored
    }

    // MARK: - Authentication

    private var isAuthenticated: Bool {
        authToken != nil && sessionId != nil
    }

    /// Authenticate with the Kanata UDP server
    func authenticate(token: String, clientName: String = "KeyPath") async -> Bool {
        AppLogger.shared.log("🔐 [UDP] Authenticating as '\(clientName)'")

        do {
            let request = UDPAuthRequest(token: token, client_name: clientName)
            let requestData = try JSONEncoder().encode(["Authenticate": request])
            let responseData = try await send(requestData)

            // Parse authentication response
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let authResponseDict = json["Authenticated"] as? [String: Any],
               let success = authResponseDict["success"] as? Bool,
               let sessionId = authResponseDict["session_id"] as? String {

                if success {
                    self.authToken = token
                    self.sessionId = sessionId
                    AppLogger.shared.log("✅ [UDP] Authentication successful, session: \(sessionId)")
                    return true
                }
            }

            AppLogger.shared.log("❌ [UDP] Authentication failed")
            return false
        } catch {
            AppLogger.shared.log("❌ [UDP] Authentication error: \(error)")
            return false
        }
    }

    /// Clear authentication state
    func clearAuthentication() {
        authToken = nil
        sessionId = nil
        AppLogger.shared.log("🧹 [UDP] Authentication cleared")
    }

    /// Check if authenticated, try to restore from shared token if not
    func ensureAuthenticated() async -> Bool {
        if isAuthenticated {
            return true
        }

        // Try to authenticate using shared token
        if let token = CommunicationSnapshot.readSharedUDPToken(), !token.isEmpty {
            return await authenticate(token: token)
        }

        return false
    }

    /// Cancel any ongoing operations (for API compatibility)
    func cancelInflightAndCloseConnection() {
        // Simplified: no inflight tracking needed for localhost IPC
        AppLogger.shared.log("🔌 [UDP] Connection reset requested")
    }

    // MARK: - Server Operations

    /// Check if UDP server is available
    func checkServerStatus(authToken: String? = nil) async -> Bool {
        AppLogger.shared.log("🌐 [UDP] Checking server status for \(host):\(port)")

        do {
            // Use RequestCurrentLayerName as a simple ping
            let pingData = try JSONEncoder().encode(["RequestCurrentLayerName": [:] as [String: String]])
            let responseData = try await send(pingData)

            if let responseString = String(data: responseData, encoding: .utf8) {
                AppLogger.shared.log("✅ [UDP] Server is responding: \(responseString.prefix(100))")

                // Try authentication if token provided
                if let token = authToken ?? CommunicationSnapshot.readSharedUDPToken(), !token.isEmpty {
                    return await authenticate(token: token)
                }

                return true
            }

            return false
        } catch {
            AppLogger.shared.log("❌ [UDP] Server check failed: \(error)")
            return false
        }
    }

    /// Validate configuration (currently not supported by kanata UDP server)
    func validateConfig(_ configContent: String) async -> UDPValidationResult {
        AppLogger.shared.log("📝 [UDP] Config validation requested (\(configContent.count) bytes)")
        AppLogger.shared.log("📝 [UDP] Note: ValidateConfig not supported by kanata - will validate on file load")
        return .success
    }

    /// Send reload command to Kanata
    func reloadConfig() async -> UDPReloadResult {
        guard isAuthenticated, let sessionId else {
            AppLogger.shared.log("❌ [UDP] Not authenticated for config reload")
            return .authenticationRequired
        }

        AppLogger.shared.log("🔄 [UDP] Triggering config reload")

        do {
            let request = UDPReloadRequest(session_id: sessionId)
            let requestData = try JSONEncoder().encode(["Reload": request])
            let responseData = try await send(requestData)

            let responseString = String(data: responseData, encoding: .utf8) ?? ""
            AppLogger.shared.log("🌐 [UDP] Reload response: \(responseString)")

            if responseString.contains("\"status\":\"Ok\"") || responseString.contains("Live reload successful") {
                AppLogger.shared.log("✅ [UDP] Config reload successful")
                return .success(response: responseString)
            } else if responseString.contains("\"status\":\"Error\"") {
                let error = extractError(from: responseString)
                AppLogger.shared.log("❌ [UDP] Config reload failed: \(error)")
                return .failure(error: error, response: responseString)
            } else if responseString.contains("AuthRequired") {
                return .authenticationRequired
            }

            AppLogger.shared.log("⚠️ [UDP] Unexpected reload response")
            return .failure(error: "Unexpected response format", response: responseString)
        } catch {
            AppLogger.shared.log("❌ [UDP] Reload error: \(error)")
            return .networkError(error.localizedDescription)
        }
    }

    /// Restart Kanata process
    func restartKanata() async -> Bool {
        guard isAuthenticated, let sessionId else {
            AppLogger.shared.log("❌ [UDP] Not authenticated for restart")
            return false
        }

        AppLogger.shared.log("🔄 [UDP] Requesting Kanata restart")

        do {
            let request = UDPRestartRequest(session_id: sessionId)
            let requestData = try JSONEncoder().encode(["Restart": request])
            let responseData = try await send(requestData)

            if let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let status = json["status"] as? String, status == "Ok" {
                AppLogger.shared.log("✅ [UDP] Kanata restart request sent")
                return true
            }

            AppLogger.shared.log("❌ [UDP] Unexpected restart response")
            return false
        } catch {
            AppLogger.shared.log("❌ [UDP] Restart failed: \(error)")
            return false
        }
    }

    // MARK: - Core Send/Receive

    /// Send UDP message and receive response with timeout
    private func send(_ data: Data) async throws -> Data {
        // Simple timeout mechanism
        try await withThrowingTaskGroup(of: Data.self) { group in
            // Main send/receive task
            group.addTask {
                try await self.sendAndReceive(data)
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

    /// Core UDP send/receive implementation
    private func sendAndReceive(_ data: Data) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            // Create connection (lightweight for localhost UDP)
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: UInt16(port)),
                using: .udp
            )

            var didComplete = false

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Send data
                    connection.send(content: data, completion: .contentProcessed { error in
                        if let error {
                            if !didComplete {
                                didComplete = true
                                continuation.resume(throwing: KeyPathError.communication(.noResponse(details: error.localizedDescription)))
                            }
                            connection.cancel()
                            return
                        }

                        // Receive response
                        connection.receiveMessage { content, _, isComplete, error in
                            defer { connection.cancel() }

                            if !didComplete {
                                didComplete = true

                                if let error {
                                    continuation.resume(throwing: KeyPathError.communication(.noResponse(details: error.localizedDescription)))
                                } else if let content {
                                    continuation.resume(returning: content)
                                } else {
                                    continuation.resume(throwing: KeyPathError.communication(.noResponse(details: "Empty response")))
                                }
                            }
                        }
                    })

                case .failed(let error):
                    if !didComplete {
                        didComplete = true
                        continuation.resume(throwing: KeyPathError.communication(.connectionFailed(error.localizedDescription)))
                    }
                    connection.cancel()

                case .cancelled:
                    if !didComplete {
                        didComplete = true
                        continuation.resume(throwing: KeyPathError.communication(.connectionFailed("Cancelled")))
                    }

                default:
                    break
                }
            }

            connection.start(queue: .global())
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
}

// MARK: - Request/Response Structures

private struct UDPAuthRequest: Codable {
    let token: String
    let client_name: String
}

private struct UDPRestartRequest: Codable {
    let session_id: String
}

private struct UDPReloadRequest: Codable {
    let session_id: String
}

// MARK: - Result Types

struct ConfigValidationError {
    let line: Int
    let column: Int
    let message: String

    var description: String {
        "Line \(line), Column \(column): \(message)"
    }
}

enum UDPValidationResult {
    case success
    case failure(errors: [ConfigValidationError])
    case authenticationRequired
    case networkError(String)
}

enum UDPReloadResult {
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