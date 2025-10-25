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
/// - Newline-delimited JSON protocol (each frame ends with \n)
/// - Proper typed decoding of ServerResponse and ServerMessage
/// - Deterministic timeout handling (no races)
public actor KanataTCPClient {
    private let host: String
    private let port: Int
    private let timeout: TimeInterval

    // Network buffer size for TCP chunks (4KB)
    private let maxChunkSize = 4096

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
        let requestId = UUID().uuidString.prefix(8)
        AppLogger.shared.log("🌐 [TCP:\(requestId)] Checking server status")

        do {
            let response = try await send(message: .requestCurrentLayerName, requestId: String(requestId))
            AppLogger.shared.log("✅ [TCP:\(requestId)] Server is available")
            return true
        } catch {
            AppLogger.shared.log("❌ [TCP:\(requestId)] Server check failed: \(error)")
            return false
        }
    }

    /// Validate configuration (not supported by kanata TCP server)
    func validateConfig(_ configContent: String) async -> TCPValidationResult {
        AppLogger.shared.log("📝 [TCP] Config validation requested (\(configContent.count) bytes)")
        AppLogger.shared.log("📝 [TCP] Note: ValidateConfig not supported by kanata - will validate on file load")
        return .success
    }

    /// Send reload command to Kanata
    func reloadConfig() async -> TCPReloadResult {
        let requestId = UUID().uuidString.prefix(8)

        // TCP doesn't require authentication - just mark as authenticated if not already
        if !isAuthenticated {
            authToken = "tcp-auto"
            sessionId = "tcp-session"
        }

        AppLogger.shared.log("🔄 [TCP:\(requestId)] Triggering config reload")

        do {
            let response = try await send(message: .reload, requestId: String(requestId))

            switch response {
            case .ok:
                AppLogger.shared.log("✅ [TCP:\(requestId)] Config reload successful")
                return .success(response: "Ok")

            case .error(let msg):
                AppLogger.shared.log("❌ [TCP:\(requestId)] Config reload failed: \(msg)")
                return .failure(error: msg, response: msg)
            }
        } catch KeyPathError.communication(.timeout) {
            AppLogger.shared.log("⏱️ [TCP:\(requestId)] Reload timed out")
            return .networkError("Request timed out")
        } catch {
            AppLogger.shared.log("❌ [TCP:\(requestId)] Reload error: \(error)")
            return .networkError(error.localizedDescription)
        }
    }

    /// Restart Kanata process
    /// NOTE: Kanata's TCP API does not support Restart command
    /// Restart must be done via launchctl or process manager
    func restartKanata() async -> Bool {
        AppLogger.shared.log("⚠️ [TCP] Restart not supported by Kanata TCP API")
        AppLogger.shared.log("⚠️ [TCP] Use launchctl or process manager to restart Kanata")
        return false
    }

    // MARK: - Core Send/Receive with Proper Protocol Handling

    /// Send a client message and receive the server response
    private func send(message: TCPClientMessage, requestId: String) async throws -> TCPServerResponse {
        // Create fresh connection
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .tcp
        )
        connection.start(queue: .global())

        do {
            // Wait for connection with timeout
            try await withTimeout(timeout) {
                try await self.waitForReady(connection: connection, requestId: requestId)
            }

            // Encode message to JSON + newline
            let encoder = JSONEncoder()
            let messageData = try encoder.encode(message) + "\n".data(using: .utf8)!

            AppLogger.shared.log("📤 [TCP:\(requestId)] Sending \(messageData.count) bytes")

            // Send with timeout
            try await withTimeout(timeout) {
                try await self.sendData(messageData, connection: connection, requestId: requestId)
            }

            // Determine what response we expect based on the message type
            let expectsServerResponse: Bool
            switch message {
            case .reload, .reloadNext:
                expectsServerResponse = true
            case .requestCurrentLayerName:
                expectsServerResponse = false
            }

            // Read response lines with timeout
            let lines = try await withTimeout(timeout) {
                try await self.readLines(from: connection, requestId: requestId, expectsServerResponse: expectsServerResponse)
            }

            // Cancel connection (we're done)
            connection.cancel()

            // Parse response
            return try parseResponse(lines: lines, requestId: requestId, expectsServerResponse: expectsServerResponse)

        } catch {
            connection.cancel()
            throw error
        }
    }

    /// Wait for TCP connection to be ready
    private func waitForReady(connection: NWConnection, requestId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumeFlag = CompletionFlag()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumeFlag.markCompleted() {
                        AppLogger.shared.log("✅ [TCP:\(requestId)] Connection ready")
                        continuation.resume()
                    }
                case .failed(let error):
                    if resumeFlag.markCompleted() {
                        AppLogger.shared.log("❌ [TCP:\(requestId)] Connection failed: \(error)")
                        continuation.resume(throwing: KeyPathError.communication(.connectionFailed(reason: error.localizedDescription)))
                    }
                case .cancelled:
                    if resumeFlag.markCompleted() {
                        AppLogger.shared.log("⚠️ [TCP:\(requestId)] Connection cancelled")
                        continuation.resume(throwing: KeyPathError.communication(.connectionFailed(reason: "Connection cancelled")))
                    }
                default:
                    break
                }
            }
        }
    }

    /// Send data on connection
    private func sendData(_ data: Data, connection: NWConnection, requestId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: KeyPathError.communication(.connectionFailed(reason: error.localizedDescription)))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Read newline-delimited lines from connection
    /// Returns array of Data, one per line (without the \n)
    /// Continues reading until we have the expected response type or connection closes
    private func readLines(from connection: NWConnection, requestId: String, expectsServerResponse: Bool) async throws -> [Data] {
        var buffer = Data()
        var lines: [Data] = []
        let decoder = JSONDecoder()
        var foundExpectedResponse = false

        AppLogger.shared.log("📦 [TCP:\(requestId)] Reading newline-delimited frames (expects \(expectsServerResponse ? "ServerResponse" : "ServerMessage"))...")

        while true {
            // Extract all complete lines from current buffer first
            while let newlineIndex = buffer.firstIndex(of: 0x0A) { // \n
                let line = buffer[0..<newlineIndex]
                lines.append(Data(line))
                AppLogger.shared.log("📦 [TCP:\(requestId)] Extracted line (\(line.count) bytes)")
                buffer.removeSubrange(0...newlineIndex) // Remove line + newline

                // Check if we've found the expected response type
                if expectsServerResponse {
                    if (try? decoder.decode(TCPServerResponse.self, from: line)) != nil {
                        foundExpectedResponse = true
                        AppLogger.shared.log("📦 [TCP:\(requestId)] Found ServerResponse, have all needed frames")
                    }
                } else {
                    if (try? decoder.decode(TCPServerMessage.self, from: line)) != nil {
                        foundExpectedResponse = true
                        AppLogger.shared.log("📦 [TCP:\(requestId)] Found ServerMessage, have all needed frames")
                    }
                }
            }

            // If we found what we need AND buffer is empty, we're done
            if foundExpectedResponse && buffer.isEmpty {
                AppLogger.shared.log("📦 [TCP:\(requestId)] Got expected response and buffer empty, exiting")
                break
            }

            // Read next chunk
            let chunk: Data? = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                let resumeFlag = CompletionFlag()
                connection.receive(minimumIncompleteLength: 1, maximumLength: maxChunkSize) { data, _, isComplete, error in
                    guard resumeFlag.markCompleted() else { return }

                    if let error {
                        continuation.resume(throwing: error)
                    } else if isComplete {
                        continuation.resume(returning: nil) // EOF
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(returning: nil) // No data
                    }
                }
            }

            guard let chunk else {
                // EOF or no data - flush buffer if non-empty
                if !buffer.isEmpty {
                    AppLogger.shared.log("📦 [TCP:\(requestId)] Connection closed, flushing final buffer (\(buffer.count) bytes)")
                    lines.append(buffer)
                }
                break
            }

            buffer.append(chunk)
            AppLogger.shared.log("📦 [TCP:\(requestId)] Read \(chunk.count) bytes (buffer: \(buffer.count))")
        }

        AppLogger.shared.log("📦 [TCP:\(requestId)] Read \(lines.count) complete lines")
        return lines
    }

    /// Parse response lines into ServerResponse
    /// Lines can be ServerResponse or ServerMessage
    /// expectsServerResponse: true for reload/reloadNext, false for health checks
    private func parseResponse(lines: [Data], requestId: String, expectsServerResponse: Bool) throws -> TCPServerResponse {
        let decoder = JSONDecoder()
        var lastResponse: TCPServerResponse?
        var foundMessage = false

        for (index, lineData) in lines.enumerated() {
            // Try ServerResponse first
            if let response = try? decoder.decode(TCPServerResponse.self, from: lineData) {
                AppLogger.shared.log("📨 [TCP:\(requestId)] Line \(index+1): ServerResponse")
                lastResponse = response

                // If it's an error, surface immediately
                if case .error(let msg) = response {
                    AppLogger.shared.log("❌ [TCP:\(requestId)] Error response: \(msg)")
                    return response
                }
            }
            // Try ServerMessage (informational)
            else if let message = try? decoder.decode(TCPServerMessage.self, from: lineData) {
                logServerMessage(message, requestId: requestId, index: index + 1)
                foundMessage = true
            }
            // Unknown frame - log but don't fail
            else {
                let preview = String(data: lineData.prefix(100), encoding: .utf8) ?? "<binary>"
                AppLogger.shared.log("⚠️ [TCP:\(requestId)] Line \(index+1): Unknown frame: \(preview)")
            }
        }

        // Return last response if we found one
        if let response = lastResponse {
            return response
        }

        // SCOPED FIX: Only message-only commands (like RequestCurrentLayerName) can succeed with just ServerMessage
        // Reload commands MUST return ServerResponse to report errors correctly
        if !expectsServerResponse && foundMessage {
            AppLogger.shared.log("✅ [TCP:\(requestId)] Got ServerMessage (no ServerResponse needed for this command)")
            return .ok
        }

        // No ServerResponse when we expected one = error
        if expectsServerResponse {
            AppLogger.shared.log("❌ [TCP:\(requestId)] Expected ServerResponse but got none (\(lines.count) lines parsed)")
        } else {
            AppLogger.shared.log("❌ [TCP:\(requestId)] No ServerResponse or ServerMessage found in \(lines.count) lines")
        }
        throw KeyPathError.communication(.invalidResponse)
    }

    /// Log server messages (informational)
    private func logServerMessage(_ message: TCPServerMessage, requestId: String, index: Int) {
        switch message {
        case .layerChange(let new):
            AppLogger.shared.log("📨 [TCP:\(requestId)] Line \(index): LayerChange → \(new)")
        case .currentLayerName(let name):
            AppLogger.shared.log("📨 [TCP:\(requestId)] Line \(index): CurrentLayerName → \(name)")
        case .configFileReload(let new):
            AppLogger.shared.log("📨 [TCP:\(requestId)] Line \(index): ConfigFileReload → \(new)")
        case .configFileReloadNew(let new):
            AppLogger.shared.log("📨 [TCP:\(requestId)] Line \(index): ConfigFileReloadNew → \(new)")
        }
    }

    /// Execute operation with timeout
    /// Cancels operation if timeout expires
    private func withTimeout<T: Sendable>(_ seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Operation task
            group.addTask {
                try await operation()
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw KeyPathError.communication(.timeout)
            }

            // Return first result and cancel other task
            guard let result = try await group.next() else {
                throw KeyPathError.communication(.timeout)
            }
            group.cancelAll()
            return result
        }
    }
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
