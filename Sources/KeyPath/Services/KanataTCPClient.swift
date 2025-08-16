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
                AppLogger.shared.log("🌐 [TCP] Invalid port \(port) for status check")
                continuation.resume(returning: false)
                return
            }

            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: .tcp
            )

            var hasResumed = false

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    AppLogger.shared.log(
                        "🌐 [TCP] Server status check: Connected to \(self.host):\(self.port)")
                    if !hasResumed {
                        hasResumed = true
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case let .failed(error):
                    AppLogger.shared.log("🌐 [TCP] Server status check: Failed to connect to \(self.host):\(self.port) - Error: \(error)")
                    AppLogger.shared.log("🌐 [TCP] Error details: \(error.localizedDescription)")
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: false)
                    }
                case .cancelled:
                    break
                default:
                    break
                }
            }

            connection.start(queue: queue)

            // Timeout after specified duration
            queue.asyncAfter(deadline: .now() + timeout) {
                if !hasResumed {
                    hasResumed = true
                    AppLogger.shared.log("🌐 [TCP] Server status check: Timeout after \(self.timeout)s connecting to \(self.host):\(self.port)")
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

    // MARK: - Low-level TCP Communication

    private func sendTCPRequest(_ data: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "kanata-tcp-request")

            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
                continuation.resume(throwing: TCPError.invalidPort)
                return
            }

            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: .tcp
            )

            var hasResumed = false

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Send the request
                    connection.send(
                        content: data,
                        completion: .contentProcessed { error in
                            if let error {
                                if !hasResumed {
                                    hasResumed = true
                                    continuation.resume(throwing: error)
                                }
                                return
                            }

                            // Receive the response - loop until complete
                            var accumulatedData = Data()

                            func receiveData() {
                                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
                                    responseData, _, isComplete, error in
                                    if let error {
                                        connection.cancel()
                                        if !hasResumed {
                                            hasResumed = true
                                            continuation.resume(throwing: error)
                                        }
                                        return
                                    }

                                    if let responseData {
                                        accumulatedData.append(responseData)
                                    }

                                    if isComplete {
                                        connection.cancel()
                                        if !hasResumed {
                                            hasResumed = true
                                            if accumulatedData.isEmpty {
                                                continuation.resume(throwing: TCPError.noResponse)
                                            } else {
                                                continuation.resume(returning: accumulatedData)
                                            }
                                        }
                                    } else {
                                        // Continue receiving more data
                                        receiveData()
                                    }
                                }
                            }

                            receiveData()
                        }
                    )

                case let .failed(error):
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: error)
                    }

                default:
                    break
                }
            }

            connection.start(queue: queue)

            // Timeout handling
            queue.asyncAfter(deadline: .now() + timeout) {
                if !hasResumed {
                    hasResumed = true
                    connection.cancel()
                    continuation.resume(throwing: TCPError.timeout)
                }
            }
        }
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

    var errorDescription: String? {
        switch self {
        case .timeout:
            "TCP request timed out"
        case .noResponse:
            "No response received from server"
        case .invalidPort:
            "Invalid TCP port number"
        }
    }
}
