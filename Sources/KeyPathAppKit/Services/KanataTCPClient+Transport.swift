import Foundation
import KeyPathCore
import Network

// MARK: - Core Send/Receive

extension KanataTCPClient {
    /// Send TCP message and receive response with timeout
    func send(_ data: Data) async throws -> Data {
        do {
            return try await sendCore(data)
        } catch {
            if shouldRetry(error) {
                AppLogger.shared.debug("🌐 [TCP] send retry after backoff: \(error)")
                try? await Task.sleep(nanoseconds: UInt64(retryBackoffSeconds * 1_000_000_000))
                closeConnection()
                return try await sendCore(data)
            }
            throw error
        }
    }

    func sendCore(_ data: Data) async throws -> Data {
        // Ensure connection is ready
        let connection = try await ensureConnectionCore()

        // Send with timeout
        return try await withThrowingTaskGroup(of: Data.self) { group in
            // Main send/receive task
            group.addTask {
                try await self.sendAndReceive(on: connection, data: data)
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

    /// Read newline-delimited data from connection
    /// Returns exactly ONE complete line (ending with \n) from the connection.
    /// Uses a persistent buffer to handle cases where Kanata sends multiple
    /// lines in a single TCP packet.
    func readUntilNewline(on connection: NWConnection) async throws -> Data {
        // Validate connection is ready before attempting read
        guard connection.state == .ready else {
            AppLogger.shared.log("❌ [TCP] readUntilNewline called on non-ready connection (state=\(connection.state))")
            throw KeyPathError.communication(.connectionFailed(reason: "Connection not ready: \(connection.state)"))
        }

        let maxLength = 65536

        // Check if we already have a complete line in the buffer
        if let (line, remaining) = extractFirstLine(from: readBuffer) {
            readBuffer = remaining
            AppLogger.shared.debug("🔌 [TCP] Returning buffered line (\(line.count) bytes, \(remaining.count) bytes remaining)")
            return line
        }

        // Thread-safe accumulator for use in NWConnection callback
        final class Accumulator: @unchecked Sendable {
            var data: Data
            init(initial: Data) { data = initial }
        }

        // Start with existing buffer contents
        let accumulator = Accumulator(initial: readBuffer)

        // No complete line in buffer, need to read from connection
        while true {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) {
                    content, _, isComplete, error in
                    if let error {
                        continuation.resume(
                            throwing: KeyPathError.communication(
                                .connectionFailed(reason: error.localizedDescription)))
                        return
                    }

                    if let content {
                        accumulator.data.append(content)
                        // Check if we now have at least one complete line (ending with \n)
                        if accumulator.data.contains(0x0A) {
                            continuation.resume()
                            return
                        }
                    }

                    if isComplete {
                        // Connection closed - return what we have if we have data, otherwise error
                        if accumulator.data.isEmpty {
                            continuation.resume(
                                throwing: KeyPathError.communication(.connectionFailed(reason: "Connection closed"))
                            )
                        } else {
                            // Return partial data if connection closed (may be valid for last line)
                            continuation.resume()
                        }
                        return
                    }

                    // No data yet, continue reading
                    continuation.resume()
                }
            }

            // Check if we have a complete line now
            if let (line, remaining) = extractFirstLine(from: accumulator.data) {
                // Store remaining data back in the persistent buffer
                readBuffer = remaining
                AppLogger.shared.debug("🔌 [TCP] Returning line (\(line.count) bytes, \(remaining.count) bytes remaining in buffer)")
                return line
            }

            // If we've accumulated too much without a newline, something is wrong
            if accumulator.data.count >= maxLength {
                throw KeyPathError.communication(
                    .connectionFailed(reason: "Response too large or malformed"))
            }
        }
    }

    /// Extract the first complete line (up to and including \n) from data.
    /// Returns the line and the remaining data, or nil if no complete line exists.
    /// Internal visibility for unit testing.
    nonisolated func extractFirstLine(from data: Data) -> (line: Data, remaining: Data)? {
        guard let newlineIndex = data.firstIndex(of: 0x0A) else {
            return nil
        }
        let lineEndIndex = data.index(after: newlineIndex)
        let line = Data(data.prefix(upTo: lineEndIndex))
        let remaining = Data(data.suffix(from: lineEndIndex))
        return (line, remaining)
    }

    /// Core TCP send/receive implementation with request_id matching
    /// Falls back to broadcast draining if server doesn't support request_id
    func sendAndReceive(on connection: NWConnection, data: Data) async throws -> Data {
        // Extract request_id from the outgoing message (if present)
        let sentRequestId = extractRequestId(from: data)

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Data, Error>) in
            let completionFlag = CompletionFlag()

            // Send data
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        if completionFlag.markCompleted() {
                            continuation.resume(
                                throwing: KeyPathError.communication(
                                    .connectionFailed(reason: error.localizedDescription)))
                        }
                        return
                    }

                    // Read response, using request_id matching if available
                    Task {
                        do {
                            var responseData: Data
                            var attempts = 0
                            let maxDrainAttempts = 50 // Prevent infinite loop - increased for high load scenarios

                            // If we sent a request_id, match responses by request_id
                            // Otherwise fall back to old broadcast draining behavior
                            repeat {
                                responseData = try await withTimeout(seconds: 5.0) {
                                    try await self.readUntilNewline(on: connection)
                                }
                                attempts += 1

                                // First check: is this an unsolicited broadcast?
                                if self.isUnsolicitedBroadcast(responseData) {
                                    if let msgStr = String(data: responseData, encoding: .utf8) {
                                        AppLogger.shared.log("🔄 [TCP] Skipping broadcast: \(msgStr.prefix(100))")
                                    }
                                    continue // Read next line
                                }

                                // Second check: if we sent request_id, verify it matches
                                if let sentId = sentRequestId {
                                    if let responseId = self.extractRequestId(from: responseData) {
                                        if responseId == sentId {
                                            // Perfect match - this is our response
                                            AppLogger.shared.debug("✅ [TCP] Matched response by request_id=\(sentId)")
                                            break
                                        } else {
                                            // Response has request_id but it doesn't match - skip it
                                            if let msgStr = String(data: responseData, encoding: .utf8) {
                                                AppLogger.shared.log(
                                                    "🔄 [TCP] Skipping mismatched response (expected=\(sentId), got=\(responseId)): \(msgStr.prefix(100))"
                                                )
                                            }
                                            continue
                                        }
                                    } else {
                                        // We sent request_id but response doesn't have one
                                        // This is likely a broadcast that slipped through - skip it
                                        // Modern Kanata versions support request_id, so rejecting is safer
                                        if let msgStr = String(data: responseData, encoding: .utf8) {
                                            AppLogger.shared.warn(
                                                "⚠️ [TCP] Response missing request_id when we sent \(sentId) - likely broadcast, skipping: \(msgStr.prefix(100))"
                                            )
                                        }
                                        continue // Skip and read next line
                                    }
                                }

                                // No request_id matching - got a response that's not a broadcast
                                break
                            } while attempts < maxDrainAttempts

                            if attempts >= maxDrainAttempts {
                                throw KeyPathError.communication(.invalidResponse)
                            }

                            if completionFlag.markCompleted() {
                                continuation.resume(returning: responseData)
                            }
                        } catch {
                            if completionFlag.markCompleted() {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
            )
        }
    }
}

// MARK: - Timeout Helper

/// Error thrown when a TCP operation times out
private struct TCPTimeoutError: Error, LocalizedError {
    var errorDescription: String? {
        "Operation timed out"
    }
}

/// Execute an async operation with a timeout
func withTimeout<T: Sendable>(
    seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Add the actual operation
        group.addTask {
            try await operation()
        }

        // Add a timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TCPTimeoutError()
        }

        // Wait for the first one to complete
        guard let result = try await group.next() else {
            throw TCPTimeoutError()
        }

        // Cancel the other task
        group.cancelAll()

        return result
    }
}
