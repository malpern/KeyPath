import Foundation
import KeyPathCore
import Network

// MARK: - Connection Management

extension KanataTCPClient {
    // MARK: - Connection Lifecycle

    func ensureConnection() async throws -> NWConnection {
        // Attempt once, then single retry with small backoff on timeout/connection failure
        do {
            return try await ensureConnectionCore()
        } catch {
            if shouldRetry(error) {
                AppLogger.shared.debug("🌐 [TCP] ensureConnection retry after backoff: \(error)")
                try? await Task.sleep(nanoseconds: UInt64(retryBackoffSeconds * 1_000_000_000))
                // Reset any half-open state
                closeConnection()
                return try await ensureConnectionCore()
            }
            throw error
        }
    }

    func ensureConnectionCore() async throws -> NWConnection {
        // Return existing connection if ready
        if let connection, connection.state == .ready {
            AppLogger.shared.log("🔌 [TCP] Reusing existing connection (state=\(connection.state))")
            return connection
        }

        // Log if we have a connection but it's not ready
        if let connection {
            AppLogger.shared.log("🔌 [TCP] Existing connection not ready (state=\(connection.state)), creating new one")
        } else {
            AppLogger.shared.log("🔌 [TCP] No existing connection, creating new one")
        }

        // Wait if already connecting
        while isConnecting {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        // Check again after waiting
        if let connection, connection.state == .ready {
            AppLogger.shared.log("🔌 [TCP] Connection became ready while waiting")
            return connection
        }

        // Create new connection
        isConnecting = true
        defer { isConnecting = false }

        AppLogger.shared.log("🔌 [TCP] Creating new connection to \(host):\(port)")
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
                        AppLogger.shared.log("🔌 [TCP] Connection state changed: \(state)")
                        switch state {
                        case .ready:
                            if completionFlag.markCompleted() {
                                continuation.resume(returning: newConnection)
                            }

                        case let .failed(error):
                            if completionFlag.markCompleted() {
                                continuation.resume(
                                    throwing: KeyPathError.communication(
                                        .connectionFailed(reason: error.localizedDescription)))
                            }
                            newConnection.cancel()

                        case .cancelled:
                            if completionFlag.markCompleted() {
                                continuation.resume(
                                    throwing: KeyPathError.communication(
                                        .connectionFailed(reason: "Connection cancelled")))
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
            AppLogger.shared.log("🔌 [TCP] Connection established successfully")
            return result
        }
    }

    func stateString(_ state: NWConnection.State?) -> String {
        guard let state else { return "nil" }
        switch state {
        case .setup: return "setup"
        case .waiting: return "waiting"
        case .preparing: return "preparing"
        case .ready: return "ready"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        @unknown default: return "unknown"
        }
    }

    func closeConnection() {
        let currentState = stateString(connection?.state)
        AppLogger.shared.log("🔌 [TCP] closeConnection() called (current state=\(currentState))")

        // Log call stack for debugging (first 5 frames)
        let stackSymbols = Thread.callStackSymbols.prefix(5).joined(separator: "\n  ")
        AppLogger.shared.debug("🔌 [TCP] closeConnection() stack trace:\n  \(stackSymbols)")

        connection?.cancel()
        connection = nil
        readBuffer.removeAll() // Clear buffered data when connection closes
    }

    /// Cancel any ongoing operations and close connection
    func cancelInflightAndCloseConnection() {
        AppLogger.shared.debug("🔌 [TCP] Closing connection")
        closeConnection()
    }

    // FIX #3: Helper to execute operations with automatic error recovery
    /// Executes an operation and closes connection if it fails with a recoverable error
    func withErrorRecovery<T: Sendable>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            // Close connection on timeout or connection failure so next call gets a fresh connection
            if shouldRetry(error) {
                AppLogger.shared.debug("🌐 [TCP] Operation failed with recoverable error, closing connection: \(error)")
                closeConnection()
            }
            throw error
        }
    }

    func shouldRetry(_ error: Error) -> Bool {
        if let kpe = error as? KeyPathError {
            switch kpe {
            case .communication(.timeout), .communication(.connectionFailed):
                return true
            default:
                return false
            }
        }
        return false
    }
}
