import Foundation
import Network

// Actor to manage request completion state safely across concurrent contexts
actor RequestCompletionState {
    private var completed = false
    
    func isCompleted() -> Bool {
        return completed
    }
    
    func markCompleted() -> Bool {
        guard !completed else { return false }
        completed = true
        return true
    }
}

/// Secure UDP client for communicating with Kanata's UDP server
/// Features: Token authentication, size gating, thread safety, secure storage
actor KanataUDPClient {
    private let host: String
    private let port: Int
    private let timeout: TimeInterval
    private let reuseConnection: Bool

    // Authentication state
    private var authToken: String?
    private var sessionId: String?
    private var sessionExpiryDate: Date?

    // Connection reuse and management
    private var activeConnection: NWConnection?
    private var connectionCreatedAt: Date?
    private let connectionMaxAge: TimeInterval = 30.0 // Close idle connections after 30 seconds

    // Inflight request tracking - prevents stale receive handler bug
    private var inflightRequest: InflightRequest?

    private struct InflightRequest {
        let id: UUID
        var isCompleted: Bool
        let cancel: () -> Void
    }

    // Size limits for UDP reliability
    static let maxUDPPayloadSize = 1200 // Safe MTU size
    private static let maxConfigSize = 1000 // Leave room for JSON wrapping

    // MARK: - Initialization

    init(host: String = "127.0.0.1", port: Int, timeout: TimeInterval = 5.0, reuseConnection: Bool = true) {
        self.host = host
        self.port = port
        self.timeout = timeout
        self.reuseConnection = reuseConnection
    }

    deinit {
        // Clean up connection on deallocation
        if let conn = activeConnection {
            conn.stateUpdateHandler = nil
            conn.cancel()
        }
        AppLogger.shared.log("📡 [UDP] Client deallocated, connection cleaned up")
    }

    // MARK: - Connection Lifecycle Management

    /// Cancel any inflight request and close the connection to prevent stale receive handlers
    func cancelInflightAndCloseConnection() {
        AppLogger.shared.log("🔌 [UDP] Cancelling inflight request and closing connection")

        if let request = inflightRequest, !request.isCompleted {
            AppLogger.shared.log("🛑 [UDP] Cancelling inflight request \(request.id)")
            request.cancel()
        }
        inflightRequest = nil

        clearBrokenConnection()
    }

    /// Timeout utility that properly cancels operations and cleans up connections
    private func withTimeout<T: Sendable>(_ seconds: TimeInterval, operation: @Sendable @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Add the main operation
            group.addTask {
                try await operation()
            }

            // Add the timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw KeyPathError.communication(.timeout)
            }

            // Wait for first completion
            let result = try await group.next()!

            // Cancel remaining tasks
            group.cancelAll()

            return result
        }
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
        guard let sessionId,
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
                let tokenToUse: String? = if let token = authToken {
                    token
                } else {
                    // Phase 2/3: Use shared token file for automatic authentication
                    CommunicationSnapshot.readSharedUDPToken()
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
            } else if case .communication = error as? KeyPathError {
                AppLogger.shared.log("❌ [UDP] Server status check failed: Communication error (timeout or no response)")
            } else {
                AppLogger.shared.log("❌ [UDP] Server status check failed: \(error)")
            }
            return false
        }
    }

    // MARK: - Configuration Validation

    /// Validate configuration via UDP server (with size gating)
    /// NOTE: Config validation via UDP is not supported by current kanata version
    func validateConfig(_ configContent: String) async -> UDPValidationResult {
        AppLogger.shared.log("📝 [UDP] Config validation requested (\(configContent.count) bytes)")
        AppLogger.shared.log("📝 [UDP] Note: ValidateConfig command not supported by kanata UDP server")
        AppLogger.shared.log("📝 [UDP] Available commands: Authenticate, ChangeLayer, RequestLayerNames, RequestCurrentLayerInfo, RequestCurrentLayerName, ActOnFakeKey, SetMouse, Reload, ReloadNext, ReloadPrev, ReloadNum, ReloadFile")

        // Return success since we can't validate via UDP
        // Config validation will happen when kanata loads the config file directly
        AppLogger.shared.log("✅ [UDP] Skipping UDP validation, config will be validated by kanata on file load")
        return .success
    }

    // MARK: - Kanata Control

    /// Restart Kanata process via UDP API
    func restartKanata() async -> Bool {
        guard isAuthenticated, let sessionId else {
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
        guard isAuthenticated, let sessionId else {
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
            if connectionAge < connectionMaxAge, !isConnectionFailed(conn.state), conn.state != .cancelled {
                return conn
            } else {
                AppLogger.shared.log("📡 [UDP] Connection too old (\(String(format: "%.1f", connectionAge))s) or invalid - creating new one")
                clearBrokenConnection()
            }
        }

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true // Better reuse behavior

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            AppLogger.shared.log("❌ [UDP] Invalid UDP port: \(port) - defaulting to 2113")
            return NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: 2113)!, using: params)
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
                Task { await self?.clearBrokenConnection() }
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

    /// Clear inflight state safely within actor context
    private func clearInflight() {
        inflightRequest = nil
    }

    private func setInflight(id: UUID, cancel: @escaping () -> Void) {
        inflightRequest = InflightRequest(id: id, isCompleted: false, cancel: cancel)
    }

    /// Wait until connection is ready with timeout (polling to avoid cross-actor captures)
    private func waitUntilReady(_ connection: NWConnection, timeout: TimeInterval) async throws {
        if connection.state == .ready { return }
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            switch connection.state {
            case .ready:
                return
            case let .failed(error):
                throw error
            case .cancelled:
                throw KeyPathError.communication(.noResponse)
            default:
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        throw KeyPathError.communication(.timeout)
    }

    // MARK: - Low-level UDP Communication

    private func sendUDPMessage(_ data: Data, requiresAuth: Bool = true) async throws -> Data {
        let requestId = UUID()
        AppLogger.shared.log("📡 [UDP] Starting request \(requestId) to \(host):\(port)")

        // Validate port early to avoid fatal errors when constructing NWEndpoint.Port
        if !(1 ... 65535).contains(port) {
            AppLogger.shared.log("📡 [UDP] ❌ Invalid port: \(port) [requestId: \(requestId)]")
            throw KeyPathError.communication(.invalidPort)
        }

        if requiresAuth, !isAuthenticated {
            throw KeyPathError.communication(.notAuthenticated)
        }

        // Size check for UDP reliability
        guard data.count <= Self.maxUDPPayloadSize else {
            throw KeyPathError.communication(.payloadTooLarge(size: data.count))
        }

        // CRITICAL: Cancel any existing inflight request to prevent stale receive handlers
        if let existingRequest = inflightRequest, !existingRequest.isCompleted {
            AppLogger.shared.log("🛑 [UDP] Cancelling existing inflight request \(existingRequest.id) before starting \(requestId)")
            existingRequest.cancel()
            clearBrokenConnection() // Tear down connection to kill stale handlers
        }

        AppLogger.shared.log("📡 [UDP] Sending message to \(host):\(port) (\(data.count) bytes) [requestId: \(requestId)]")
        // Sanitized logging with proper redaction
        let sanitized = sanitizeForLog(data)
        AppLogger.shared.log("📡 [UDP] Message content: \(sanitized) [requestId: \(requestId)]")

        // Get or create connection (fresh if previous was torn down)
        let connection = getOrCreateConnection()

        do {
            try await waitUntilReady(connection, timeout: timeout)
        } catch {
            // Clear broken connection and retry once
            AppLogger.shared.log("⚠️ [UDP] Connection not ready, retrying with fresh connection [requestId: \(requestId)]")
            clearBrokenConnection()
            let newConnection = getOrCreateConnection()
            try await waitUntilReady(newConnection, timeout: timeout)
        }

        // Use withTimeout to enforce timeout with proper cleanup
        do {
            return try await withTimeout(timeout) {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    // Use an actor to manage request completion state safely
                    let completionState = RequestCompletionState()

                    // Set up inflight request tracking
                    let cancelRequest = {
                        AppLogger.shared.log("🛑 [UDP] Cancelling request \(requestId) -> tearing down connection")
                        Task { await self.clearBrokenConnection() }
                    }

                    Task { await self.setInflight(id: requestId, cancel: cancelRequest) }

                    // Log local endpoint to verify stable binding
                    if let localEndpoint = connection.currentPath?.localEndpoint {
                        AppLogger.shared.log("📡 [UDP] Local endpoint: \(localEndpoint) [requestId: \(requestId)]")
                    } else {
                        AppLogger.shared.log("📡 [UDP] WARNING: No local endpoint available yet [requestId: \(requestId)]")
                    }

                    // CRITICAL FIX: Arm receive BEFORE send to avoid localhost race condition
                    // On localhost, server responds instantly before receive handler gets installed
                    AppLogger.shared.log("📡 [UDP] Arming receive handler BEFORE send to prevent race condition [requestId: \(requestId)]")

                    connection.receiveMessage { responseData, context, _, error in
                        Task {
                            // Only process if this request hasn't completed
                            guard await !completionState.isCompleted() else {
                                AppLogger.shared.log("🚫 [UDP] Ignoring receive for completed request \(requestId)")
                                return
                            }

                            if let error {
                                AppLogger.shared.log("📡 [UDP] ❌ Receive error: \(error) [requestId: \(requestId)]")
                                if await completionState.markCompleted() {
                                    await self.clearInflight()
                                    continuation.resume(throwing: error)
                                }
                                return
                            }

                            if let responseData {
                                AppLogger.shared.log("📡 [UDP] ✅ Received response: \(responseData.count) bytes [requestId: \(requestId)]")
                                if let context {
                                    AppLogger.shared.log("📡 [UDP] Response context: \(context) [requestId: \(requestId)]")
                                }
                                if await completionState.markCompleted() {
                                    await self.clearInflight()
                                    continuation.resume(returning: responseData)
                                }
                            } else {
                                AppLogger.shared.log("📡 [UDP] ❌ No response data received [requestId: \(requestId)]")
                                if await completionState.markCompleted() {
                                    await self.clearInflight()
                                    continuation.resume(throwing: KeyPathError.communication(.noResponse))
                                }
                            }
                        }
                    }

                    // Now send after receive handler is armed
                    AppLogger.shared.log("📡 [UDP] Sending message after receive handler is armed [requestId: \(requestId)]")
                    connection.send(content: data, completion: .contentProcessed { error in
                        if let error {
                            AppLogger.shared.log("📡 [UDP] ❌ Send error: \(error) [requestId: \(requestId)]")
                            Task {
                                if await completionState.markCompleted() {
                                    await self.clearInflight()
                                    continuation.resume(throwing: error)
                                }
                            }
                            return
                        }

                        // Log local endpoint after send to verify stability
                        if let localEndpoint = connection.currentPath?.localEndpoint {
                            AppLogger.shared.log("📡 [UDP] ✅ Message sent from local endpoint: \(localEndpoint) [requestId: \(requestId)]")
                        } else {
                            AppLogger.shared.log("📡 [UDP] ⚠️ Message sent but no local endpoint info available [requestId: \(requestId)]")
                        }
                        AppLogger.shared.log("📡 [UDP] ✅ Message sent - receive handler already armed [requestId: \(requestId)]")
                    })
                }
            }
        } catch {
            // CRITICAL CLEANUP: On timeout or other error, ensure inflight request is cleaned up
            AppLogger.shared.log("⏰ [UDP] Request \(requestId) failed with error: \(error)")
            if let request = inflightRequest, request.id == requestId {
                AppLogger.shared.log("🧹 [UDP] Cleaning up inflight request \(requestId) after error")
                inflightRequest = nil
                request.cancel() // This will tear down connection to prevent stale handlers
            }
            throw error
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
        throw KeyPathError.communication(.invalidResponse)
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

/// UDP-specific errors
/// UDP communication errors
///
/// - Deprecated: Use `KeyPathError.communication(...)` instead for consistent error handling
@available(*, deprecated, message: "Use KeyPathError.communication(...) instead")
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
            "UDP request timed out"
        case .noResponse:
            "No response received from server"
        case .invalidPort:
            "Invalid UDP port number"
        case .invalidResponse:
            "Invalid or malformed response from server"
        case .notAuthenticated:
            "Not authenticated with UDP server"
        case let .payloadTooLarge(size):
            "Payload too large for UDP (\(size) bytes). Maximum: \(KanataUDPClient.maxUDPPayloadSize) bytes"
        }
    }

    /// Convert to KeyPathError for consistent error handling
    var asKeyPathError: KeyPathError {
        switch self {
        case .timeout:
            return .communication(.timeout)
        case .noResponse:
            return .communication(.noResponse)
        case .invalidPort:
            return .communication(.invalidPort)
        case .invalidResponse:
            return .communication(.invalidResponse)
        case .notAuthenticated:
            return .communication(.notAuthenticated)
        case let .payloadTooLarge(size):
            return .communication(.payloadTooLarge(size: size))
        }
    }
}
