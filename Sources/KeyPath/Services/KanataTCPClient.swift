import Foundation
import Network

/// TCP client for communicating with Kanata's TCP server for config validation
class KanataTCPClient {
    private let host: String
    private let port: Int
    private let timeout: TimeInterval

    // MARK: - Initialization

    init(host: String = "127.0.0.1", port: Int, timeout: TimeInterval = 5.0) {
        self.host = host
        self.port = port
        self.timeout = timeout
    }

    // MARK: - Connection Status

    /// Check if TCP server is available and responding
    func checkServerStatus() async -> Bool {
        AppLogger.shared.log("🌐 [TCP] Starting server status check for \(host):\(port) with timeout \(timeout)s")
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "kanata-tcp-status")

            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
                AppLogger.shared.log("🌐 [TCP] ❌ Invalid port \(port) for status check")
                continuation.resume(returning: false)
                return
            }

            AppLogger.shared.log("🌐 [TCP] Creating connection to \(host):\(port)")
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: .tcp
            )

            var hasResumed = false

            connection.stateUpdateHandler = { state in
                AppLogger.shared.log("🌐 [TCP] Connection state changed: \(state)")
                switch state {
                case .setup:
                    AppLogger.shared.log("🌐 [TCP] Connection setup")
                case let .waiting(error):
                    AppLogger.shared.log("🌐 [TCP] Connection waiting: \(error)")
                case .preparing:
                    AppLogger.shared.log("🌐 [TCP] Connection preparing")
                case .ready:
                    AppLogger.shared.log(
                        "🌐 [TCP] ✅ Server status check: Connected to \(self.host):\(self.port)")
                    if !hasResumed {
                        hasResumed = true
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case let .failed(error):
                    AppLogger.shared.log("🌐 [TCP] ❌ Server status check: Failed to connect to \(self.host):\(self.port) - Error: \(error)")
                    AppLogger.shared.log("🌐 [TCP] Error details: \(error.localizedDescription)")
                    if let nwError = error as? NWError {
                        AppLogger.shared.log("🌐 [TCP] NWError type: \(nwError)")
                        switch nwError {
                        case let .posix(posixError):
                            AppLogger.shared.log("🌐 [TCP] POSIX error: \(posixError) (\(posixError.rawValue))")
                        case let .dns(dnsError):
                            AppLogger.shared.log("🌐 [TCP] DNS error: \(dnsError)")
                        case let .tls(tlsError):
                            AppLogger.shared.log("🌐 [TCP] TLS error: \(tlsError)")
                        default:
                            AppLogger.shared.log("🌐 [TCP] Other network error: \(nwError)")
                        }
                    }
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: false)
                    }
                case .cancelled:
                    AppLogger.shared.log("🌐 [TCP] Connection cancelled")
                }
            }

            AppLogger.shared.log("🌐 [TCP] Starting connection on queue")
            connection.start(queue: queue)

            // Timeout after specified duration
            queue.asyncAfter(deadline: .now() + timeout) {
                AppLogger.shared.log("🌐 [TCP] Timeout handler triggered after \(self.timeout)s")
                if !hasResumed {
                    hasResumed = true
                    AppLogger.shared.log("🌐 [TCP] ⏰ Server status check: Timeout after \(self.timeout)s connecting to \(self.host):\(self.port)")
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Config Validation

    /// Validate configuration via TCP server
    /// Returns validation result with errors if any
    func validateConfig(_ configContent: String) async -> TCPValidationResult {
        let request = TCPValidationRequest(config_content: configContent)

        do {
            let requestData = try JSONEncoder().encode(["ValidateConfig": request])
            let responseData = try await sendTCPRequest(requestData)

            let response = try JSONDecoder().decode(TCPValidationResponse.self, from: responseData)

            if response.success {
                AppLogger.shared.log("✅ [TCP] Config validation successful")
                return .success
            } else {
                let errors =
                    response.errors?.map { error in
                        ConfigValidationError(
                            line: error.line,
                            column: error.column,
                            message: error.message
                        )
                    } ?? []

                AppLogger.shared.log("❌ [TCP] Config validation failed with \(errors.count) errors")
                return .failure(errors: errors)
            }

        } catch {
            AppLogger.shared.log("❌ [TCP] Config validation error: \(error)")
            return .networkError(error.localizedDescription)
        }
    }

    /// Restart Kanata process via TCP API (for post-permission changes)
    /// Use this after user grants permissions to apply changes immediately
    func restartKanata() async -> Bool {
        AppLogger.shared.log("🔄 [TCP] Requesting Kanata restart")

        do {
            // Use correct PR #1759 API format: {"Restart": {}}
            let requestData = try JSONEncoder().encode(["Restart": [:] as [String: String]])
            let responseData = try await sendTCPRequest(requestData)

            // Check if we got {"status":"Ok"} response
            if let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let status = json["status"] as? String, status == "Ok"
            {
                AppLogger.shared.log("✅ [TCP] Kanata restart request sent successfully")
                return true
            } else {
                AppLogger.shared.log("❌ [TCP] Unexpected restart response format")
                return false
            }
        } catch {
            AppLogger.shared.log("❌ [TCP] Kanata restart failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Low-level TCP Communication

    private func sendTCPRequest(_ data: Data) async throws -> Data {
        AppLogger.shared.log("🌐 [TCP] Starting TCP request to \(host):\(port)")
        AppLogger.shared.log("🌐 [TCP] Request data: \(data.count) bytes")
        if let requestString = String(data: data, encoding: .utf8) {
            AppLogger.shared.log("🌐 [TCP] Request content: \(requestString)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "kanata-tcp-request")

            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
                AppLogger.shared.log("🌐 [TCP] ❌ Invalid port \(port)")
                continuation.resume(throwing: TCPError.invalidPort)
                return
            }

            AppLogger.shared.log("🌐 [TCP] Creating TCP connection")
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: .tcp
            )

            var hasResumed = false

            connection.stateUpdateHandler = { state in
                AppLogger.shared.log("🌐 [TCP] Request connection state: \(state)")
                switch state {
                case .setup:
                    AppLogger.shared.log("🌐 [TCP] Request connection setup")
                case let .waiting(error):
                    AppLogger.shared.log("🌐 [TCP] Request connection waiting: \(error)")
                case .preparing:
                    AppLogger.shared.log("🌐 [TCP] Request connection preparing")
                case .ready:
                    AppLogger.shared.log("🌐 [TCP] Request connection ready - sending data")
                    // Send the request
                    connection.send(
                        content: data,
                        completion: .contentProcessed { error in
                            if let error {
                                AppLogger.shared.log("🌐 [TCP] ❌ Send error: \(error)")
                                if !hasResumed {
                                    hasResumed = true
                                    continuation.resume(throwing: error)
                                }
                                return
                            }

                            AppLogger.shared.log("🌐 [TCP] ✅ Data sent successfully - starting receive")
                            // Receive the response - parse JSON messages as they arrive
                            var accumulatedData = Data()
                            var receiveCount = 0

                            func receiveData() {
                                receiveCount += 1
                                AppLogger.shared.log("🌐 [TCP] Receive attempt #\(receiveCount)")
                                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
                                    responseData, _, isComplete, error in
                                    if let error {
                                        AppLogger.shared.log("🌐 [TCP] ❌ Receive error: \(error)")
                                        connection.cancel()
                                        if !hasResumed {
                                            hasResumed = true
                                            continuation.resume(throwing: error)
                                        }
                                        return
                                    }

                                    if let responseData {
                                        AppLogger.shared.log("🌐 [TCP] Received chunk: \(responseData.count) bytes")
                                        accumulatedData.append(responseData)
                                        AppLogger.shared.log("🌐 [TCP] Total accumulated: \(accumulatedData.count) bytes")

                                        // Try to parse JSON messages from accumulated data
                                        if let responseMessage = self.tryParseExpectedResponse(from: accumulatedData) {
                                            AppLogger.shared.log("🌐 [TCP] ✅ Found expected response - completing request")
                                            connection.cancel()
                                            if !hasResumed {
                                                hasResumed = true
                                                continuation.resume(returning: responseMessage)
                                            }
                                            return
                                        }
                                    } else {
                                        AppLogger.shared.log("🌐 [TCP] Received nil data chunk")
                                    }

                                    AppLogger.shared.log("🌐 [TCP] Connection complete: \(isComplete)")
                                    if isComplete {
                                        // Connection closed - return what we have
                                        connection.cancel()
                                        if !hasResumed {
                                            hasResumed = true
                                            if accumulatedData.isEmpty {
                                                AppLogger.shared.log("🌐 [TCP] ❌ No response data received")
                                                continuation.resume(throwing: TCPError.noResponse)
                                            } else {
                                                AppLogger.shared.log("🌐 [TCP] ✅ Connection closed - \(accumulatedData.count) bytes received")
                                                continuation.resume(returning: accumulatedData)
                                            }
                                        }
                                    } else {
                                        AppLogger.shared.log("🌐 [TCP] Continuing to receive more data...")
                                        // Continue receiving more data
                                        receiveData()
                                    }
                                }
                            }

                            receiveData()
                        }
                    )
                case let .failed(error):
                    AppLogger.shared.log("🌐 [TCP] ❌ Request connection failed: \(error)")
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: error)
                    }
                case .cancelled:
                    AppLogger.shared.log("🌐 [TCP] Request connection cancelled")
                }
            }

            AppLogger.shared.log("🌐 [TCP] Starting request connection")
            connection.start(queue: queue)

            // Timeout handling
            queue.asyncAfter(deadline: .now() + timeout) {
                AppLogger.shared.log("🌐 [TCP] Request timeout handler triggered after \(self.timeout)s")
                if !hasResumed {
                    hasResumed = true
                    AppLogger.shared.log("🌐 [TCP] ⏰ Request timeout after \(self.timeout)s")
                    connection.cancel()
                    continuation.resume(throwing: TCPError.timeout)
                }
            }
        }
    }

    /// Try to parse expected response from accumulated data
    /// Kanata sends newline-delimited JSON messages, we want to extract the MacosPermissions response
    private func tryParseExpectedResponse(from data: Data) -> Data? {
        guard let dataString = String(data: data, encoding: .utf8) else {
            AppLogger.shared.log("🌐 [TCP] Cannot convert data to UTF-8 string")
            return nil
        }

        AppLogger.shared.log("🌐 [TCP] Parsing accumulated data: \(dataString)")

        // Split by newlines and try to parse each JSON message
        let lines = dataString.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            AppLogger.shared.log("🌐 [TCP] Checking JSON line: \(trimmed)")

            do {
                if let json = try JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] {
                    AppLogger.shared.log("🌐 [TCP] Parsed JSON with keys: \(Array(json.keys))")

                    // Check if this is the MacosPermissions response we want
                    if json["MacosPermissions"] != nil {
                        AppLogger.shared.log("🌐 [TCP] ✅ Found MacosPermissions message!")
                        return Data(trimmed.utf8)
                    }
                }
            } catch {
                AppLogger.shared.log("🌐 [TCP] Failed to parse JSON line: \(error)")
                // Continue to next line
            }
        }

        AppLogger.shared.log("🌐 [TCP] No MacosPermissions message found yet")
        return nil
    }
}

// MARK: - Data Models

/// Request structure for TCP config validation
private struct TCPValidationRequest: Codable {
    let config_content: String
}

/// Response structure from TCP config validation
private struct TCPValidationResponse: Codable {
    let success: Bool
    let errors: [TCPValidationError]?
}

/// Individual validation error from TCP response
private struct TCPValidationError: Codable {
    let line: Int
    let column: Int
    let message: String
}

/// Public validation result
enum TCPValidationResult {
    case success
    case failure(errors: [ConfigValidationError])
    case networkError(String)
}

/// Public configuration error structure
struct ConfigValidationError {
    let line: Int
    let column: Int
    let message: String

    var description: String {
        "Line \(line), Column \(column): \(message)"
    }
}

/// TCP-specific errors
enum TCPError: Error, LocalizedError {
    case timeout
    case noResponse
    case invalidPort
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .timeout:
            "TCP request timed out"
        case .noResponse:
            "No response received from server"
        case .invalidPort:
            "Invalid TCP port number"
        case .invalidResponse:
            "Invalid or malformed response from server"
        }
    }
}
