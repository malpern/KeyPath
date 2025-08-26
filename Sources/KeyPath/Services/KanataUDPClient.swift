import Foundation
import Network

/// Secure UDP client for communicating with Kanata's UDP server
/// Features: Token authentication, size gating, thread safety, secure storage
actor KanataUDPClient {
    private let host: String
    private let port: Int
    private let timeout: TimeInterval

    // Authentication state
    private var authToken: String?
    private var sessionId: String?
    private var sessionExpiryDate: Date?

    // Connection reuse
    private var activeConnection: NWConnection?

    // Size limits for UDP reliability
    private static let maxUDPPayloadSize = 1200 // Safe MTU size
    private static let maxConfigSize = 1000 // Leave room for JSON wrapping

    // MARK: - Initialization

    init(host: String = "127.0.0.1", port: Int, timeout: TimeInterval = 3.0) {
        self.host = host
        self.port = port
        self.timeout = timeout
    }

    // MARK: - Authentication

    /// Authenticate with Kanata UDP server using provided token
    /// Returns true if authentication successful
    func authenticate(token: String, clientName: String = "KeyPath") async -> Bool {
        // Check payload size before sending
        let authRequest = UDPAuthRequest(token: token, client_name: clientName)
        guard let requestData = try? JSONEncoder().encode(["Authenticate": authRequest]),
              requestData.count <= Self.maxUDPPayloadSize
        else {
            AppLogger.shared.log("❌ [UDP] Authentication payload too large for UDP (\(requestData?.count ?? 0) bytes)")
            return false
        }
        AppLogger.shared.log("🔐 [UDP] Attempting authentication")

        do {
            let responseData = try await sendUDPMessage(requestData)
            let response = try JSONDecoder().decode([String: UDPAuthResponse].self, from: responseData)

            if let authResult = response["AuthResult"], authResult.success {
                authToken = token
                sessionId = authResult.session_id
                sessionExpiryDate = Date().addingTimeInterval(TimeInterval(authResult.expires_in_seconds))

                // Store session info in Keychain service for persistence
                await MainActor.run {
                    KeychainService.shared.cacheSessionExpiry(
                        sessionId: authResult.session_id,
                        expiryDate: self.sessionExpiryDate!
                    )
                }

                AppLogger.shared.log("✅ [UDP] Authentication successful")
                AppLogger.shared.log("🔐 [UDP] Session established (expires in \(authResult.expires_in_seconds)s)")

                return true
            } else {
                AppLogger.shared.log("❌ [UDP] Authentication failed")
                return false
            }
        } catch {
            AppLogger.shared.log("❌ [UDP] Authentication error: \(error)")
            return false
        }
    }

    /// Check if current session is still valid
    var isAuthenticated: Bool {
        guard let sessionId = sessionId,
              let expiryDate = sessionExpiryDate,
              !sessionId.isEmpty,
              Date() < expiryDate
        else {
            return false
        }
        return true
    }

    /// Clear authentication state and cleanup connections
    func clearAuthentication() {
        authToken = nil
        sessionId = nil
        sessionExpiryDate = nil

        // Close active connection
        activeConnection?.cancel()
        activeConnection = nil

        // Clear session cache
        Task { @MainActor in
            KeychainService.shared.clearSessionCache()
        }

        AppLogger.shared.log("🔐 [UDP] Authentication cleared")
    }

    // MARK: - Server Status

    /// Check if UDP server is available and authenticate if token provided
    func checkServerStatus(authToken: String? = nil) async -> Bool {
        AppLogger.shared.log("🌐 [UDP] Checking server status for \(host):\(port)")

        // Simple ping message to test connectivity
        do {
            let pingData = try JSONEncoder().encode(["Ping": [:] as [String: String]])
            _ = try await sendUDPMessage(pingData, requiresAuth: false)

            AppLogger.shared.log("✅ [UDP] Server is responding")

            // If auth token provided, attempt authentication
            if let token = authToken {
                return await authenticate(token: token)
            }

            return true
        } catch {
            AppLogger.shared.log("❌ [UDP] Server status check failed: \(error)")
            return false
        }
    }

    // MARK: - Configuration Validation

    /// Validate configuration via UDP server (with size gating)
    func validateConfig(_ configContent: String) async -> UDPValidationResult {
        guard isAuthenticated, let sessionId = sessionId else {
            AppLogger.shared.log("❌ [UDP] Not authenticated for config validation")
            return .authenticationRequired
        }

        // Check if config is too large for UDP
        if configContent.count > Self.maxConfigSize {
            AppLogger.shared.log("📦 [UDP] Config too large for UDP (\(configContent.count) bytes > \(Self.maxConfigSize)), skipping")
            return .networkError("Configuration too large for UDP. Use TCP for large configs.")
        }

        let request = UDPValidationRequest(config_content: configContent, session_id: sessionId)

        do {
            let requestData = try JSONEncoder().encode(["ValidateConfig": request])
            let responseData = try await sendUDPMessage(requestData)

            if let response = try? JSONDecoder().decode([String: UDPValidationResponse].self, from: responseData),
               let validationResult = response["ValidationResult"] {
                if validationResult.success {
                    AppLogger.shared.log("✅ [UDP] Config validation successful")
                    return .success
                } else {
                    let errors = validationResult.errors?.map { error in
                        ConfigValidationError(
                            line: error.line,
                            column: error.column,
                            message: error.message
                        )
                    } ?? []

                    AppLogger.shared.log("❌ [UDP] Config validation failed with \(errors.count) errors")
                    return .failure(errors: errors)
                }
            } else {
                // Check for auth errors
                return try handleAuthErrors(responseData)
            }
        } catch {
            AppLogger.shared.log("❌ [UDP] Config validation error: \(error)")
            return .networkError(error.localizedDescription)
        }
    }

    // MARK: - Kanata Control

    /// Restart Kanata process via UDP API
    func restartKanata() async -> Bool {
        guard isAuthenticated, let sessionId = sessionId else {
            AppLogger.shared.log("❌ [UDP] Not authenticated for restart")
            return false
        }

        AppLogger.shared.log("🔄 [UDP] Requesting Kanata restart")

        do {
            let request = UDPRestartRequest(session_id: sessionId)
            let requestData = try JSONEncoder().encode(["Restart": request])
            let responseData = try await sendUDPMessage(requestData)

            // Check for success response
            if let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let status = json["status"] as? String, status == "Ok" {
                AppLogger.shared.log("✅ [UDP] Kanata restart request sent successfully")
                return true
            } else {
                _ = try handleAuthErrors(responseData)
                AppLogger.shared.log("❌ [UDP] Unexpected restart response format")
                return false
            }
        } catch {
            AppLogger.shared.log("❌ [UDP] Kanata restart failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Send reload command to Kanata
    func reloadConfig() async -> UDPReloadResult {
        guard isAuthenticated, let sessionId = sessionId else {
            AppLogger.shared.log("❌ [UDP] Not authenticated for config reload")
            return .authenticationRequired
        }

        AppLogger.shared.log("🔄 [UDP] Triggering config reload")

        do {
            let request = UDPReloadRequest(session_id: sessionId)
            let requestData = try JSONEncoder().encode(["Reload": request])
            let responseData = try await sendUDPMessage(requestData)

            let responseString = String(data: responseData, encoding: .utf8) ?? ""
            AppLogger.shared.log("🌐 [UDP] Reload response: \(responseString)")

            // Parse response for success/failure
            if responseString.contains("\"status\":\"Ok\"") || responseString.contains("Live reload successful") {
                AppLogger.shared.log("✅ [UDP] Config reload successful")
                return .success(response: responseString)
            } else if responseString.contains("\"status\":\"Error\"") {
                let errorMsg = extractErrorFromResponse(responseString)
                AppLogger.shared.log("❌ [UDP] Config reload failed: \(errorMsg)")
                return .failure(error: errorMsg, response: responseString)
            } else {
                // Check for auth errors
                if let authResult = try? handleAuthErrors(responseData) {
                    switch authResult {
                    case .authenticationRequired:
                        return .authenticationRequired
                    default:
                        break
                    }
                }

                AppLogger.shared.log("⚠️ [UDP] Unexpected reload response")
                return .failure(error: "Unexpected response format", response: responseString)
            }
        } catch {
            AppLogger.shared.log("❌ [UDP] Config reload error: \(error)")
            return .networkError(error.localizedDescription)
        }
    }

    // MARK: - Low-level UDP Communication

    private func sendUDPMessage(_ data: Data, requiresAuth: Bool = true) async throws -> Data {
        if requiresAuth && !isAuthenticated {
            throw UDPError.notAuthenticated
        }

        // Size check for UDP reliability
        guard data.count <= Self.maxUDPPayloadSize else {
            throw UDPError.payloadTooLarge(data.count)
        }

        AppLogger.shared.log("📡 [UDP] Sending message to \(host):\(port) (\(data.count) bytes)")
        // Redact sensitive message content from logs
        if let messageString = String(data: data, encoding: .utf8), !messageString.contains("token") {
            AppLogger.shared.log("📡 [UDP] Message content: \(messageString)")
        } else {
            AppLogger.shared.log("📡 [UDP] Message content: [REDACTED - contains sensitive data]")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "kanata-udp-client")

            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
                continuation.resume(throwing: UDPError.invalidPort)
                return
            }

            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: .udp
            )

            var hasResumed = false

            connection.stateUpdateHandler = { state in
                AppLogger.shared.log("📡 [UDP] Connection state: \(state)")
                switch state {
                case .ready:
                    // Send the message
                    connection.send(content: data, completion: .contentProcessed { error in
                        if let error = error {
                            AppLogger.shared.log("📡 [UDP] ❌ Send error: \(error)")
                            if !hasResumed {
                                hasResumed = true
                                connection.cancel()
                                continuation.resume(throwing: error)
                            }
                            return
                        }

                        AppLogger.shared.log("📡 [UDP] ✅ Message sent - waiting for response")

                        // Receive the response
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { responseData, _, _, error in
                            if let error = error {
                                AppLogger.shared.log("📡 [UDP] ❌ Receive error: \(error)")
                                connection.cancel()
                                if !hasResumed {
                                    hasResumed = true
                                    continuation.resume(throwing: error)
                                }
                                return
                            }

                            if let responseData = responseData {
                                AppLogger.shared.log("📡 [UDP] ✅ Received response: \(responseData.count) bytes")
                                connection.cancel()
                                if !hasResumed {
                                    hasResumed = true
                                    continuation.resume(returning: responseData)
                                }
                            } else {
                                AppLogger.shared.log("📡 [UDP] ❌ No response data received")
                                connection.cancel()
                                if !hasResumed {
                                    hasResumed = true
                                    continuation.resume(throwing: UDPError.noResponse)
                                }
                            }
                        }
                    })
                case let .failed(error):
                    AppLogger.shared.log("📡 [UDP] ❌ Connection failed: \(error)")
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: error)
                    }
                case .cancelled:
                    AppLogger.shared.log("📡 [UDP] Connection cancelled")
                default:
                    break
                }
            }

            connection.start(queue: queue)

            // Store connection for potential reuse
            if !requiresAuth {
                activeConnection = connection
            }

            // Timeout handling
            queue.asyncAfter(deadline: .now() + timeout) {
                if !hasResumed {
                    hasResumed = true
                    AppLogger.shared.log("📡 [UDP] ⏰ Request timeout after \(self.timeout)s")
                    connection.cancel()
                    continuation.resume(throwing: UDPError.timeout)
                }
            }
        }
    }

    // MARK: - Response Parsing

    private func handleAuthErrors(_ responseData: Data) throws -> UDPValidationResult {
        if let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
            if json["AuthRequired"] != nil {
                AppLogger.shared.log("🔐 [UDP] Authentication required")
                clearAuthentication()
                return .authenticationRequired
            } else if json["SessionExpired"] != nil {
                AppLogger.shared.log("🔐 [UDP] Session expired")
                clearAuthentication()
                return .authenticationRequired
            }
        }
        throw UDPError.invalidResponse
    }

    private func extractErrorFromResponse(_ response: String) -> String {
        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = json["msg"] as? String {
            return msg
        }
        return "Unknown error from Kanata"
    }
}

// MARK: - Data Models

/// Authentication request structure
private struct UDPAuthRequest: Codable {
    let token: String
    let client_name: String
}

/// Authentication response structure
private struct UDPAuthResponse: Codable {
    let success: Bool
    let session_id: String
    let expires_in_seconds: Int
}

/// Config validation request with session
private struct UDPValidationRequest: Codable {
    let config_content: String
    let session_id: String
}

/// Config validation response
private struct UDPValidationResponse: Codable {
    let success: Bool
    let errors: [UDPValidationError]?
}

/// Individual validation error
private struct UDPValidationError: Codable {
    let line: Int
    let column: Int
    let message: String
}

/// Restart request with session
private struct UDPRestartRequest: Codable {
    let session_id: String
}

/// Reload request with session
private struct UDPReloadRequest: Codable {
    let session_id: String
}

// MARK: - Result Types

/// UDP validation result
enum UDPValidationResult {
    case success
    case failure(errors: [ConfigValidationError])
    case authenticationRequired
    case networkError(String)
}

/// UDP reload result
enum UDPReloadResult {
    case success(response: String)
    case failure(error: String, response: String)
    case authenticationRequired
    case networkError(String)

    var isSuccess: Bool {
        switch self {
        case .success:
            return true
        default:
            return false
        }
    }

    var errorMessage: String? {
        switch self {
        case let .failure(error, _):
            return error
        case .authenticationRequired:
            return "Authentication required"
        case let .networkError(error):
            return error
        case .success:
            return nil
        }
    }

    var response: String? {
        switch self {
        case let .success(response):
            return response
        case let .failure(_, response):
            return response
        default:
            return nil
        }
    }
}

/// UDP-specific errors
enum UDPError: Error, LocalizedError {
    case timeout
    case noResponse
    case invalidPort
    case invalidResponse
    case notAuthenticated
    case payloadTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "UDP request timed out"
        case .noResponse:
            return "No response received from server"
        case .invalidPort:
            return "Invalid UDP port number"
        case .invalidResponse:
            return "Invalid or malformed response from server"
        case .notAuthenticated:
            return "Not authenticated with UDP server"
        case let .payloadTooLarge(size):
            return "Payload too large for UDP (\(size) bytes). Maximum: \(KanataUDPClient.maxUDPPayloadSize) bytes"
        }
    }
}
