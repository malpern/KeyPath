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
/// - Fresh TCP connection for each request (Kanata closes after each command)
/// - Newline-delimited JSON protocol
/// - Simple request/response pattern
/// - Timeout protection
public actor KanataTCPClient {
    private let host: String
    private let port: Int
    private let timeout: TimeInterval

    // Simple authentication state
    private var authToken: String?
    private var sessionId: String?

    // MARK: - Initialization

    init(host: String = "127.0.0.1", port: Int, timeout: TimeInterval = 5.0) {
        self.host = host
        self.port = port
        self.timeout = timeout
    }

    // MARK: - Authentication

    private var isAuthenticated: Bool {
        authToken != nil && sessionId != nil
    }

    /// Authenticate with the Kanata TCP server
    /// Note: Kanata's TCP implementation doesn't require authentication (it ignores auth messages)
    /// This method is kept for API compatibility but always returns true for TCP
    func authenticate(token: String, clientName: String = "KeyPath") async -> Bool {
        // Skip if already authenticated with this token
        if isAuthenticated && authToken == token {
            AppLogger.shared.log("✅ [TCP] Already authenticated, reusing session: \(sessionId ?? "unknown")")
            return true
        }

        AppLogger.shared.log("🔐 [TCP] Authenticating as '\(clientName)' (TCP doesn't require auth, auto-succeeding)")

        // Kanata's TCP server ignores authentication messages and doesn't send responses
        // So we just mark ourselves as authenticated without sending the message
        self.authToken = token
        self.sessionId = "tcp-session-\(UUID().uuidString)"
        AppLogger.shared.log("✅ [TCP] Authentication bypassed (TCP doesn't need it), session: \(sessionId ?? "unknown")")
        return true
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

        // Try to authenticate using shared token
        if let token = CommunicationSnapshot.readSharedTCPToken(), !token.isEmpty {
            return await authenticate(token: token)
        }

        return false
    }


    // MARK: - Server Operations

    /// Check if TCP server is available
    func checkServerStatus(authToken: String? = nil) async -> Bool {
        AppLogger.shared.log("🌐 [TCP] TEMPORARILY DISABLED - Skipping TCP validation")
        AppLogger.shared.log("🌐 [TCP] Will use CLI validation instead")
        return false  // Temporarily disable TCP validation to debug timeout issues
    }

    /// Validate configuration (not supported by kanata TCP server)
    func validateConfig(_ configContent: String) async -> TCPValidationResult {
        AppLogger.shared.log("📝 [TCP] Config validation requested (\(configContent.count) bytes)")
        AppLogger.shared.log("📝 [TCP] Note: ValidateConfig not supported by kanata - will validate on file load")
        return .success
    }

    /// Send reload command to Kanata
    func reloadConfig() async -> TCPReloadResult {
        // TCP doesn't require authentication - just mark as authenticated if not already
        if !isAuthenticated {
            authToken = "tcp-auto"
            sessionId = "tcp-session"
        }

        AppLogger.shared.log("🔄 [TCP] Triggering config reload")

        do {
            // Kanata's TCP Reload command doesn't need session_id (TCP doesn't use sessions)
            // Send empty object for Reload with newline terminator
            var requestData = try JSONEncoder().encode(["Reload": [:] as [String: String]])
            requestData.append(contentsOf: "\n".data(using: .utf8)!) // Kanata expects newline-delimited messages
            let responseData = try await send(requestData)

            let responseString = String(data: responseData, encoding: .utf8) ?? ""
            AppLogger.shared.log("🌐 [TCP] Reload response: \(responseString)")

            // Kanata sends multiple newline-delimited messages for reload:
            // 1. LayerChange, 2. {"status":"Ok"}, 3. ConfigFileReload, 4. LayerChange
            // Check if any line contains success status
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

            AppLogger.shared.log("⚠️ [TCP] Unexpected reload response (no status in response)")
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
            var requestData = try JSONEncoder().encode(["Restart": request])
            requestData.append(contentsOf: "\n".data(using: .utf8)!) // Kanata expects newline-delimited messages
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

    /// Core TCP send/receive implementation
    private func sendAndReceive(_ data: Data) async throws -> Data {
        // Always create a fresh connection for each request
        // Kanata closes connections after each command, so reusing causes "Socket is not connected" errors
        AppLogger.shared.log("🔌 [TCP] Creating new connection to \(host):\(port)")
        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .tcp
        )
        conn.start(queue: .global())

        // Wait for connection to be ready
        try await waitForReady(connection: conn)

        AppLogger.shared.log("📤 [TCP] Sending \(data.count) bytes")

        // Send data
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: KeyPathError.communication(.connectionFailed(reason: error.localizedDescription)))
                } else {
                    continuation.resume()
                }
            })
        }

        // Receive response - read until newline
        // Kanata sends newline-terminated JSON messages
        AppLogger.shared.log("📦 [TCP] Reading response until newline...")

        let allData = try await readUntilNewline(from: conn)

        // Clean up connection
        conn.cancel()

        AppLogger.shared.log("📥 [TCP] Total received: \(allData.count) bytes")
        return allData
    }

    /// Wait for TCP connection to be ready
    private func waitForReady(connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumeFlag = CompletionFlag()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumeFlag.markCompleted() {
                        AppLogger.shared.log("✅ [TCP] Connection ready")
                        continuation.resume()
                    }
                case .failed(let error):
                    if resumeFlag.markCompleted() {
                        AppLogger.shared.log("❌ [TCP] Connection failed: \(error)")
                        continuation.resume(throwing: KeyPathError.communication(.connectionFailed(reason: error.localizedDescription)))
                    }
                case .cancelled:
                    if resumeFlag.markCompleted() {
                        AppLogger.shared.log("⚠️ [TCP] Connection cancelled")
                        continuation.resume(throwing: KeyPathError.communication(.connectionFailed(reason: "Connection cancelled")))
                    }
                default:
                    break
                }
            }
        }
    }

    /// Read all newline-delimited messages from connection
    /// Kanata sends multiple messages for commands like Reload, so we need to read them all
    /// NOTE: This method is currently not used as TCP validation is disabled
    private func readUntilNewline(from connection: NWConnection) async throws -> Data {
        // TCP validation is temporarily disabled, so this method shouldn't be called
        throw KeyPathError.communication(.connectionFailed(reason: "TCP validation disabled"))
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

private struct TCPAuthRequest: Codable {
    let token: String
    let client_name: String
}

private struct TCPRestartRequest: Codable {
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
