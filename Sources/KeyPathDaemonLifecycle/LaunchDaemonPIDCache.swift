import Foundation
import KeyPathCore

/// Cache for LaunchDaemon PID lookups to prevent repeated expensive launchctl calls
/// Solves race condition where rapid process checks cause inconsistent conflict detection
public actor LaunchDaemonPIDCache {
    // MARK: - State

    private var cachedPID: pid_t?
    public private(set) var lastUpdate: Date?
    private let cacheTimeout: TimeInterval = 10.0 // 10 second cache
    private let launchctlTimeout: TimeInterval = 3.0 // 3 second launchctl timeout

    // MARK: - Public API

    /// Get cached PID or fetch fresh one with timeout protection
    /// Returns tuple of (pid, confidence) where confidence indicates reliability
    public func getCachedPIDWithConfidence() async -> (pid: pid_t?, confidence: CacheConfidence) {
        let result = await getCachedPID()

        if let lastUpdate {
            let age = Date().timeIntervalSince(lastUpdate)
            if age < cacheTimeout / 2 {
                return (result, .high)
            } else if age < cacheTimeout {
                return (result, .medium)
            } else {
                return (result, .low)
            }
        }

        return (result, result != nil ? .low : .none)
    }

    /// Get cached PID or fetch fresh one with timeout protection
    public func getCachedPID() async -> pid_t? {
        // Check if cache is still valid
        if let lastUpdate,
           let cachedPID,
           Date().timeIntervalSince(lastUpdate) < cacheTimeout {
            AppLogger.shared.log("💾 [PIDCache] Using cached PID: \(cachedPID) (age: \(Int(Date().timeIntervalSince(lastUpdate)))s)")
            return cachedPID
        }

        // Cache expired or no cache - fetch fresh PID
        AppLogger.shared.log("🔄 [PIDCache] Cache expired or empty, fetching fresh PID...")

        do {
            let freshPID = try await fetchLaunchDaemonPIDWithTimeout()

            // Update cache
            cachedPID = freshPID
            lastUpdate = Date()

            AppLogger.shared.log("💾 [PIDCache] Cached fresh PID: \(freshPID ?? -1)")
            return freshPID
        } catch is TimeoutError {
            AppLogger.shared.log("⏰ [PIDCache] launchctl timed out after \(launchctlTimeout)s")

            // Return stale cache if available for timeout errors
            if let staleCache = cachedPID {
                AppLogger.shared.log("⚠️ [PIDCache] Using stale cache due to timeout: \(staleCache)")
                return staleCache
            }

            return nil
        } catch {
            AppLogger.shared.log("❌ [PIDCache] Failed to fetch PID: \(error)")

            // Return stale cache if available for other errors
            if let staleCache = cachedPID {
                AppLogger.shared.log("⚠️ [PIDCache] Using stale cache due to error: \(staleCache)")
                return staleCache
            }

            return nil
        }
    }

    /// Invalidate cache to force fresh lookup on next access
    public func invalidateCache() {
        cachedPID = nil
        lastUpdate = nil
        AppLogger.shared.log("🗑️ [PIDCache] Cache invalidated")
    }

    // MARK: - Private Implementation
    private func fetchLaunchDaemonPIDWithTimeout() async throws -> pid_t? {
        try await withThrowingTaskGroup(of: pid_t?.self) { group in
            group.addTask {
                try await self.runLaunchctlPrint()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.launchctlTimeout * 1_000_000_000))
                throw TimeoutError()
            }

            guard let result = try await group.next() else {
                group.cancelAll()
                throw TimeoutError()
            }
            group.cancelAll()
            return result
        }
    }

    private func runLaunchctlPrint() async throws -> pid_t? {
        try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.launchPath = "/bin/launchctl"
            task.arguments = ["print", "system/com.keypath.kanata"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe() // Discard error output

            task.terminationHandler = { task in
                if task.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    let pid = self.extractPIDFromLaunchctlOutput(output)
                    continuation.resume(returning: pid)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private nonisolated func extractPIDFromLaunchctlOutput(_ output: String) -> pid_t? {
        // Look for pattern like "pid = 97324"
        if let pidRange = output.range(of: "pid = ") {
            let pidStart = output.index(pidRange.upperBound, offsetBy: 0)
            // Find the end of the PID number
            var pidEnd = pidStart
            while pidEnd < output.endIndex, output[pidEnd].isNumber {
                pidEnd = output.index(after: pidEnd)
            }

            let pidString = String(output[pidStart ..< pidEnd])
            let pid = pid_t(pidString)

            let isRunning = output.contains("state = running")

            AppLogger.shared.log("🔍 [PIDCache] Extracted from launchctl: pid=\(pid ?? -1), running=\(isRunning)")

            // Only return PID if service is actually running
            return isRunning ? pid : nil
        }

        AppLogger.shared.log("🔍 [PIDCache] No PID found in launchctl output")
        return nil
    }
}

/// Timeout error for launchctl operations
public struct TimeoutError: Error {
    public let message = "launchctl operation timed out"
}

/// Confidence level for cached PID data
public enum CacheConfidence: Sendable {
    case high // Fresh cache (< 5s old)
    case medium // Valid cache (5-10s old)
    case low // Stale cache (> 10s old) or error fallback
    case none // No cache available
}

