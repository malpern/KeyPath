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
                try? await Task.sleep(for: .seconds(retryBackoffSeconds))
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

        // If another call is already connecting, register as a waiter and suspend until
        // that attempt completes. This replaces the old busy-wait loop which had an actor
        // reentrancy race: Task.sleep suspension points let multiple callers slip through
        // simultaneously, creating duplicate connections.
        if isConnecting {
            AppLogger.shared.log("🔌 [TCP] Connection in progress, waiting for result...")
            return try await withCheckedThrowingContinuation { continuation in
                connectionWaiters.append(continuation)
            }
        }

        // Create new connection
        isConnecting = true

        AppLogger.shared.log("🔌 [TCP] Creating new connection to \(host):\(port)")
        let newConnection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .tcp
        )

        connection = newConnection

        // Wait for connection to be ready with timeout.
        // On completion (success or failure), resume all queued waiters.
        do {
            let result = try await withThrowingTaskGroup(of: NWConnection.self) { group in
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
                                            .connectionFailed(reason: error.localizedDescription)
                                        )
                                    )
                                }
                                newConnection.cancel()

                            case .cancelled:
                                if completionFlag.markCompleted() {
                                    continuation.resume(
                                        throwing: KeyPathError.communication(
                                            .connectionFailed(reason: "Connection cancelled")
                                        )
                                    )
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
                    try await Task.sleep(for: .seconds(self.timeout))
                    newConnection.cancel() // Cancel the connection on timeout
                    throw KeyPathError.communication(.timeout)
                }

                // Return first result and cancel other task
                let result = try await group.next()!
                group.cancelAll()
                AppLogger.shared.log("🔌 [TCP] Connection established successfully")
                return result
            }

            // Resume all waiters with the successful connection
            let waiters = connectionWaiters
            connectionWaiters.removeAll()
            isConnecting = false
            for waiter in waiters {
                waiter.resume(returning: result)
            }
            return result
        } catch {
            // Resume all waiters with the error
            let waiters = connectionWaiters
            connectionWaiters.removeAll()
            isConnecting = false
            for waiter in waiters {
                waiter.resume(throwing: error)
            }
            throw error
        }
    }

    // MARK: - Send Serialization

    /// Acquire exclusive send/receive access for the shared connection.
    ///
    /// Uses FIFO handoff semantics with cancellation cleanup to avoid orphaned continuations.
    func acquireSendLock() async throws {
        try Task.checkCancellation()
        if !isSending {
            isSending = true
            return
        }

        let waiterId = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sendWaiters.append(SendWaiter(id: waiterId, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelSendWaiter(id: waiterId) }
        }

        do {
            try Task.checkCancellation()
        } catch {
            // This waiter already received the handoff; pass it forward.
            releaseSendLock()
            throw error
        }
    }

    /// Release send/receive access and wake the next waiter if present.
    func releaseSendLock() {
        guard isSending else { return }
        if sendWaiters.isEmpty {
            isSending = false
            return
        }
        // Keep isSending=true while handing off to the next waiter.
        let next = sendWaiters.removeFirst()
        next.continuation.resume()
    }

    private func cancelSendWaiter(id: UUID) {
        guard let index = sendWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = sendWaiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
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

        AppLogger.shared.debug("🔌 [TCP] closeConnection()")

        connection?.cancel()
        connection = nil
        readBuffer.removeAll() // Clear buffered data when connection closes
        cachedHello = nil // Force fresh hello on next connection
        isSending = false
        let waiters = sendWaiters
        sendWaiters.removeAll()
        let teardownError = KeyPathError.communication(.connectionFailed(reason: "Connection closed"))
        for waiter in waiters {
            waiter.continuation.resume(throwing: teardownError)
        }
    }

    /// Cancel any ongoing operations and close connection
    func cancelInflightAndCloseConnection() {
        AppLogger.shared.debug("🔌 [TCP] Closing connection")
        closeConnection()
    }

    /// FIX #3: Helper to execute operations with automatic error recovery
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
