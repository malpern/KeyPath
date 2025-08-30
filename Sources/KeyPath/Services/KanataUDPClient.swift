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

    // Connection reuse and management
    private var activeConnection: NWConnection?
    private var connectionCreatedAt: Date?
    private let connectionMaxAge: TimeInterval = 30.0 // Close idle connections after 30 seconds

    // Size limits for UDP reliability
    static let maxUDPPayloadSize = 1200 // Safe MTU size
    private static let maxConfigSize = 1000 // Leave room for JSON wrapping

    // MARK: - Initialization

    init(host: String = "127.0.0.1", port: Int, timeout: TimeInterval = 5.0) {
        self.host = host
        self.port = port
        self.timeout = timeout
    }

    deinit {
        // Clean up connection on deallocation
        if let conn = activeConnection {
            conn.stateUpdateHandler = nil
            conn.cancel()
        }
        AppLogger.shared.log("📡 [UDP] Client deallocated, connection cleaned up")
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
            AppLogger.shared.log("❌ [UDP] Authentication payload too large for UDP")
            return false
        }
        AppLogger.shared.log("🔐 [UDP] Attempting authentication")

        do {
            let responseData = try await sendUDPMessage(requestData, requiresAuth: false)
            let response = try JSONDecoder().decode([String: UDPAuthResponse].self, from: responseData)

            if let authResult = response["AuthResult"], authResult.success {
                authToken = token
                sessionId = authResult.session_id
                sessionExpiryDate = Date().addingTimeInterval(TimeInterval(authResult.expires_in_seconds))

                // Store session info in Keychain service for persistence
                let expiryDate = sessionExpiryDate!
                await MainActor.run {
                    KeychainService.shared.cacheSessionExpiry(
                        sessionId: authResult.session_id,
                        expiryDate: expiryDate
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

    /// Automatically authenticate using shared token if not already authenticated
    func ensureAuthenticated() async -> Bool {
        if isAuthenticated {
            return true
        }

        // Phase 2/3: Use shared token file for automatic authentication
        guard let sharedToken = CommunicationSnapshot.readSharedUDPToken(), !sharedToken.isEmpty else {
            AppLogger.shared.log("⚠️ [UDP] No shared token available for automatic authentication")
            return false
        }

        return await authenticate(token: sharedToken)
    }

    // MARK: - Server Status

    /// Check if UDP server is available and authenticate if token provided
    func checkServerStatus(authToken: String? = nil) async -> Bool {
        AppLogger.shared.log("🌐 [UDP] Checking server status for \(host):\(port)")

        // Use RequestCurrentLayerName which is a valid kanata command
        do {
            let pingData = try JSONEncoder().encode(["RequestCurrentLayerName": [:] as [String: String]])
            let responseData = try await sendUDPMessage(pingData, requiresAuth: false)

            // Parse the response
            if let responseString = String(data: responseData, encoding: .utf8) {
                AppLogger.shared.log("🌐 [UDP] Server response: \(responseString)")

                // Any valid response (including "AuthRequired") means server is working
                if responseString.contains("AuthRequired") || responseString.contains("Auth") {
                    AppLogger.shared.log("✅ [UDP] Server is responding (auth required)")
                } else {
                    AppLogger.shared.log("✅ [UDP] Server is responding")
                }

                // Try authentication with provided token or shared token
                let tokenToUse: String?
                if let token = authToken {
                    tokenToUse = token
                } else {
                    // Phase 2/3: Use shared token file for automatic authentication
                    tokenToUse = CommunicationSnapshot.readSharedUDPToken()
                }

                if let token = tokenToUse, !token.isEmpty {
                    return await authenticate(token: token)
                }

                return true
            } else {
                AppLogger.shared.log("❌ [UDP] Invalid response format")
                return false
            }
        } catch {
            // Provide more detailed error information for better diagnosis
            if let nwError = error as? NWError {
                switch nwError {
                case let .posix(posixError):
                    if posixError == .ECONNREFUSED {
                        AppLogger.shared.log("❌ [UDP] Server status check failed: Connection refused (server likely starting up)")
                    } else {
                        AppLogger.shared.log("❌ [UDP] Server status check failed: POSIX error \(posixError)")
                    }
                case .dns:
                    AppLogger.shared.log("❌ [UDP] Server status check failed: DNS resolution error")
                case .tls:
                    AppLogger.shared.log("❌ [UDP] Server status check failed: TLS error")
                default:
                    AppLogger.shared.log("❌ [UDP] Server status check failed: NWError \(nwError)")
                }
            } else if error is UDPError {
                AppLogger.shared.log("❌ [UDP] Server status check failed: UDP timeout or no response")
            } else {
                AppLogger.shared.log("❌ [UDP] Server status check failed: \(error)")
            }
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

    // MARK: - Connection Management

    /// Create or reuse UDP connection to avoid race conditions
    private func getOrCreateConnection() -> NWConnection {
        // Check if existing connection is still valid and not too old
        if let conn = activeConnection, let createdAt = connectionCreatedAt {
            let connectionAge = Date().timeIntervalSince(createdAt)
            if connectionAge < connectionMaxAge && !isConnectionFailed(conn.state) && conn.state != .cancelled {
                return conn
            } else {
                AppLogger.shared.log("📡 [UDP] Connection too old (\(String(format: "%.1f", connectionAge))s) or invalid - creating new one")
                clearBrokenConnection()
            }
        }

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true // Better reuse behavior

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            fatalError("Invalid UDP port: \(port)")
        }

        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: params
        )

        let queue = DispatchQueue(label: "kanata-udp-client-\(port)")
        conn.stateUpdateHandler = { [weak self] state in
            AppLogger.shared.log("📡 [UDP] Connection state: \(state)")
            if case .failed = state {
                // Drop broken connection so next call recreates it
                Task { @MainActor in
                    await self?.clearBrokenConnection()
                }
            }
        }
        conn.start(queue: queue)
        activeConnection = conn
        connectionCreatedAt = Date()
        AppLogger.shared.log("📡 [UDP] Created new connection to \(host):\(port)")
        return conn
    }

    /// Check if connection is in failed state
    private func isConnectionFailed(_ state: NWConnection.State) -> Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    /// Clear broken connection and properly clean up handlers
    private func clearBrokenConnection() {
        if let conn = activeConnection {
            // Reset state handler to prevent leaks
            conn.stateUpdateHandler = nil
            conn.cancel()
            AppLogger.shared.log("📡 [UDP] Canceled connection and cleared handlers")
        }
        activeConnection = nil
        connectionCreatedAt = nil
        AppLogger.shared.log("📡 [UDP] Cleared broken connection")
    }

    /// Wait until connection is ready with timeout
    private func waitUntilReady(_ connection: NWConnection, timeout: TimeInterval) async throws {
        if connection.state == .ready {
            return
        }

        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "kanata-udp-ready-wait")
            var hasResumed = false

            // Connection establishment timeout
            let timeoutTimer = queue.asyncAfter(deadline: .now() + timeout) {
                if !hasResumed {
                    hasResumed = true
                    AppLogger.shared.log("📡 [UDP] ⏰ Connection establishment timeout after \(timeout)s")
                    continuation.resume(throwing: UDPError.timeout)
                }
            }

            // Check current state or wait for ready
            if connection.state == .ready {
                if !hasResumed {
                    hasResumed = true
                    continuation.resume()
                }
                return
            }

            // Install temporary state handler to wait for ready
            let originalHandler = connection.stateUpdateHandler
            var timeoutTask: Task<Void, Never>?

            let cleanup = {
                connection.stateUpdateHandler = originalHandler
                timeoutTask?.cancel()
            }

            connection.stateUpdateHandler = { [weak connection] state in
                originalHandler?(state) // Call original handler first

                if !hasResumed {
                    switch state {
                    case .ready:
                        hasResumed = true
                        cleanup()
                        continuation.resume()
                    case let .failed(error):
                        hasResumed = true
                        cleanup()
                        continuation.resume(throwing: error)
                    case .cancelled:
                        hasResumed = true
                        cleanup()
                        continuation.resume(throwing: UDPError.noResponse)
                    default:
                        break
                    }
                }
            }

            // Timeout cleanup
            timeoutTask = Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !hasResumed {
                    cleanup()
                }
            }
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
        // Sanitized logging with proper redaction
        let sanitized = sanitizeForLog(data)
        AppLogger.shared.log("📡 [UDP] Message content: \(sanitized)")

        // Use connection reuse to avoid race conditions
        let connection = getOrCreateConnection()

        do {
            try await waitUntilReady(connection, timeout: timeout)
        } catch {
            // Clear broken connection and retry once
            clearBrokenConnection()
            let newConnection = getOrCreateConnection()
            try await waitUntilReady(newConnection, timeout: timeout)
        }

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            // Log local endpoint to verify stable binding
            if let localEndpoint = connection.currentPath?.localEndpoint {
                AppLogger.shared.log("📡 [UDP] Local endpoint: \(localEndpoint)")
            } else {
                AppLogger.shared.log("📡 [UDP] WARNING: No local endpoint available yet")
            }

            // CRITICAL FIX: Arm receive BEFORE send to avoid localhost race condition
            // On localhost, server responds instantly before receive handler gets installed
            AppLogger.shared.log("📡 [UDP] Arming receive handler BEFORE send to prevent race condition")

            connection.receiveMessage { responseData, context, _, error in
                if let error = error {
                    AppLogger.shared.log("📡 [UDP] ❌ Receive error: \(error)")
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: error)
                    }
                    return
                }

                if let responseData = responseData {
                    AppLogger.shared.log("📡 [UDP] ✅ Received response: \(responseData.count) bytes")
                    if let context = context {
                        AppLogger.shared.log("📡 [UDP] Response context: \(context)")
                    }
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: responseData)
                    }
                } else {
                    AppLogger.shared.log("📡 [UDP] ❌ No response data received")
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: UDPError.noResponse)
                    }
                }
            }

            // Now send after receive handler is armed
            AppLogger.shared.log("📡 [UDP] Sending message after receive handler is armed")
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    AppLogger.shared.log("📡 [UDP] ❌ Send error: \(error)")
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: error)
                    }
                    return
                }

                // Log local endpoint after send to verify stability
                if let localEndpoint = connection.currentPath?.localEndpoint {
                    AppLogger.shared.log("📡 [UDP] ✅ Message sent from local endpoint: \(localEndpoint)")
                } else {
                    AppLogger.shared.log("📡 [UDP] ⚠️ Message sent but no local endpoint info available")
                }
                AppLogger.shared.log("📡 [UDP] ✅ Message sent - receive handler already armed")
            })

            // Overall timeout for the entire request-response cycle
            let queue = DispatchQueue(label: "kanata-udp-timeout")
            queue.asyncAfter(deadline: .now() + timeout) {
                if !hasResumed {
                    hasResumed = true
                    AppLogger.shared.log("📡 [UDP] ⏰ Request-response timeout after \(self.timeout)s")
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

    /// Sanitize log data by redacting sensitive fields
    private func sanitizeForLog(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "[non-JSON payload redacted]"
        }

        let sensitiveFields = ["token", "auth_token", "session_id"]

        // Recursively redact sensitive fields
        guard let sanitized = redactSensitiveFields(json, fields: sensitiveFields) as? [String: Any] else {
            return "[redaction failed]"
        }

        guard let safeData = try? JSONSerialization.data(withJSONObject: sanitized),
              let result = String(data: safeData, encoding: .utf8)
        else {
            return "[JSON serialization failed]"
        }

        return result
    }

    /// Recursively redact sensitive fields from JSON object
    private func redactSensitiveFields(_ object: Any, fields: [String]) -> Any {
        if var dict = object as? [String: Any] {
            for field in fields {
                if dict[field] != nil {
                    dict[field] = "***"
                }
            }
            // Recursively process nested objects
            for (key, value) in dict {
                dict[key] = redactSensitiveFields(value, fields: fields)
            }
            return dict
        } else if let array = object as? [Any] {
            return array.map { redactSensitiveFields($0, fields: fields) }
        } else {
            return object
        }
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

/// Public configuration error structure
struct ConfigValidationError {
    let line: Int
    let column: Int
    let message: String

    var description: String {
        "Line \(line), Column \(column): \(message)"
    }
}

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
