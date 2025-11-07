import ApplicationServices
@preconcurrency import Combine
import Foundation
import IOKit.hid
import KeyPathCore

// (Removed deprecated OracleError - now using KeyPathError directly)

/// 🔮 THE ORACLE - Single source of truth for all permission detection in KeyPath
///
/// This actor eliminates the chaos of multiple conflicting permission detection methods.
/// It provides deterministic, hierarchical permission checking with clear source precedence.
public actor PermissionOracle {
    public static let shared = PermissionOracle()

    // MARK: - Published Properties (for real-time sync)

    /// Notifies observers when permission state changes
    public nonisolated let statusUpdatePublisher = PassthroughSubject<Date, Never>()

    // MARK: - Core Types

    public enum Status: Equatable, Sendable {
        case granted
        case denied
        case error(String)
        case unknown

        public var isReady: Bool {
            if case .granted = self { return true }
            return false
        }

        public var isBlocking: Bool {
            if case .denied = self { return true }
            if case .error = self { return true }
            return false
        }
    }

    public struct PermissionSet: Sendable {
        public let accessibility: Status
        public let inputMonitoring: Status
        public let source: String
        public let confidence: Confidence
        public let timestamp: Date

        public init(accessibility: Status, inputMonitoring: Status, source: String, confidence: Confidence, timestamp: Date) {
            self.accessibility = accessibility
            self.inputMonitoring = inputMonitoring
            self.source = source
            self.confidence = confidence
            self.timestamp = timestamp
        }

        public var hasAllPermissions: Bool {
            accessibility.isReady && inputMonitoring.isReady
        }
    }

    public struct Snapshot: Sendable {
        public let keyPath: PermissionSet
        public let kanata: PermissionSet
        public let timestamp: Date

        public init(keyPath: PermissionSet, kanata: PermissionSet, timestamp: Date) {
            self.keyPath = keyPath
            self.kanata = kanata
            self.timestamp = timestamp
        }

        /// System is ready when both apps have all required permissions
        public var isSystemReady: Bool {
            keyPath.hasAllPermissions && kanata.hasAllPermissions
        }

        /// Get the first blocking permission issue (user-facing error message)
        public var blockingIssue: String? {
            // Check KeyPath permissions first (needed for UI functionality)
            if keyPath.accessibility.isBlocking {
                return "KeyPath needs Accessibility permission - enable in System Settings > Privacy & Security > Accessibility"
            }

            if keyPath.inputMonitoring.isBlocking {
                return "KeyPath needs Input Monitoring permission - enable in System Settings > Privacy & Security > Input Monitoring"
            }

            // Check Kanata permissions
            if kanata.accessibility.isBlocking || kanata.inputMonitoring.isBlocking {
                return "Kanata needs permissions - use the Installation Wizard to grant Accessibility and Input Monitoring"
            }

            return nil
        }

        /// Diagnostic information for troubleshooting
        public var diagnosticSummary: String {
            """
            🔮 Permission Oracle Snapshot (\(String(format: "%.3f", Date().timeIntervalSince(timestamp)))s ago)

            KeyPath [\(keyPath.source), \(keyPath.confidence)]:
              • Accessibility: \(keyPath.accessibility)
              • Input Monitoring: \(keyPath.inputMonitoring)

            Kanata [\(kanata.source), \(kanata.confidence)]:
              • Accessibility: \(kanata.accessibility)
              • Input Monitoring: \(kanata.inputMonitoring)

            System Ready: \(isSystemReady)
            """
        }
    }

    public enum Confidence: Equatable, CustomStringConvertible, Sendable {
        case high // UDP API, Official Apple APIs
        case low // Unknown/unavailable states (TCC fallback removed)

        public var description: String {
            switch self {
            case .high: "high"
            case .low: "low"
            }
        }
    }

    // MARK: - State Management

    private var lastSnapshot: Snapshot?
    private var lastSnapshotTime: Date?

    /// Cache TTL for sub-2-second goal
    private let cacheTTL: TimeInterval = 1.5

    public init() {
        AppLogger.shared.log("🔮 [Oracle] Permission Oracle initialized - ending the chaos!")
    }

    // MARK: - 🎯 THE ONLY PUBLIC API

    /// Force cache invalidation - useful after UDP configuration changes
    public func invalidateCache() {
        AppLogger.shared.log("🔮 [Oracle] Cache invalidated - next check will be fresh")
        lastSnapshot = nil
        lastSnapshotTime = nil
    }

    /// Get current permission snapshot - THE authoritative permission state
    ///
    /// This is the ONLY method other components should call.
    /// No more direct PermissionService calls, no more guessing from logs.
    public func currentSnapshot() async -> Snapshot {
        // Fast-path for unit tests: avoid heavy OS calls and network timeouts
        if TestEnvironment.isRunningTests {
            // Honor cache semantics in tests to keep behavior deterministic
            if let cachedTime = lastSnapshotTime,
               let cached = lastSnapshot,
               Date().timeIntervalSince(cachedTime) < cacheTTL {
                AppLogger.shared.log("🔮 [Oracle] (Test) Returning cached snapshot")
                return cached
            }

            let now = Date()
            let placeholder = PermissionSet(
                accessibility: .unknown,
                inputMonitoring: .unknown,
                source: "test.placeholder",
                confidence: .low,
                timestamp: now
            )
            let snap = Snapshot(keyPath: placeholder, kanata: placeholder, timestamp: now)
            lastSnapshot = snap
            lastSnapshotTime = now
            AppLogger.shared.log("🔮 [Oracle] Test mode snapshot generated (non-blocking)")
            return snap
        }

        // Return cached result if fresh
        if let cachedTime = lastSnapshotTime,
           let cached = lastSnapshot,
           Date().timeIntervalSince(cachedTime) < cacheTTL {
            AppLogger.shared.log("🔮 [Oracle] Returning cached snapshot (age: \(String(format: "%.3f", Date().timeIntervalSince(cachedTime)))s)")
            return cached
        }

        AppLogger.shared.log("🔮 [Oracle] Generating fresh permission snapshot")
        let start = Date()

        // Get KeyPath permissions (local, always authoritative)
        let keyPathSet = checkKeyPathPermissions()

        // Get Kanata permissions (UDP primary, functional verification)
        let kanataSet = await checkKanataPermissions()

        let snapshot = Snapshot(
            keyPath: keyPathSet,
            kanata: kanataSet,
            timestamp: Date()
        )

        let duration = Date().timeIntervalSince(start)
        AppLogger.shared.log("🔮 [Oracle] Permission snapshot complete in \(String(format: "%.3f", duration))s")
        AppLogger.shared.log("🔮 [Oracle] System ready: \(snapshot.isSystemReady)")
        if let issue = snapshot.blockingIssue {
            AppLogger.shared.log("🔮 [Oracle] Blocking issue: \(issue)")
        }

        // Cache the result
        lastSnapshot = snapshot
        lastSnapshotTime = snapshot.timestamp

        // Notify observers of status update
        statusUpdatePublisher.send(snapshot.timestamp)

        return snapshot
    }

    /// Force refresh (bypass cache) - use after permission changes
    public func forceRefresh() async -> Snapshot {
        AppLogger.shared.log("🔮 [Oracle] Forcing permission refresh (cache invalidated)")
        lastSnapshot = nil
        lastSnapshotTime = nil
        return await currentSnapshot()
    }

    // MARK: - KeyPath Permission Detection (Always Authoritative)

    private func checkKeyPathPermissions() -> PermissionSet {
        let start = Date()

        // Accessibility check via official Apple API (no prompt)
        let axGranted = AXIsProcessTrusted()
        let accessibility: Status = axGranted ? .granted : .denied

        // Input Monitoring check via official Apple API (no prompt, no CGEvent tap)
        // Skip during startup if this is the first call to avoid UI freezing
        var inputMonitoring: Status = .unknown

        if FeatureFlags.shared.startupModeActive {
            // During startup, skip the potentially blocking IOHIDCheckAccess call
            AppLogger.shared.log("🔮 [Oracle] Startup mode - skipping IOHIDCheckAccess to prevent UI freeze")
            inputMonitoring = .unknown
        } else {
            // Normal operation - safe to call IOHIDCheckAccess
            let accessCheckStart = Date()
            let accessType = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
            let accessCheckDuration = Date().timeIntervalSince(accessCheckStart)

            if accessCheckDuration > 2.0 {
                AppLogger.shared.log("⚠️ [Oracle] IOHIDCheckAccess took \(String(format: "%.3f", accessCheckDuration))s - unusually slow")
            }

            let imGranted = accessType == kIOHIDAccessTypeGranted
            inputMonitoring = imGranted ? .granted : .denied
        }

        let duration = Date().timeIntervalSince(start)
        AppLogger.shared.log("🔮 [Oracle] KeyPath permission check completed in \(String(format: "%.3f", duration))s - AX: \(accessibility), IM: \(inputMonitoring)")

        let isStartupMode = if case .unknown = inputMonitoring { true } else { false }

        return PermissionSet(
            accessibility: accessibility,
            inputMonitoring: inputMonitoring,
            source: isStartupMode ? "keypath.startup-mode" : "keypath.official-apis",
            confidence: isStartupMode ? .low : .high,
            timestamp: Date()
        )
    }

    // MARK: - Kanata Permission Detection (GUI Context - ARCHITECTURE.md Current Workaround)

    private func checkKanataPermissions() async -> PermissionSet {
        let kanataPath = resolveKanataExecutablePath()

        // IMPORTANT: IOHIDCheckAccess() reflects the calling process only and
        // cannot be used to check another binary's Input Monitoring permission.
        // For Kanata, use TCC for both AX and IM.

        AppLogger.shared.log("🔮 [Oracle] Checking TCC database for Kanata (AX + IM)")
        let (tccAX, tccIM) = await checkTCCForKanata(executablePath: kanataPath)

        let accessibility: Status = tccAX ?? .unknown
        let inputMonitoring: Status = tccIM ?? .unknown

        var sourceParts: [String] = []
        var confidence: Confidence = .high

        switch accessibility { case .granted, .denied: sourceParts.append("tcc-ax"); default: break }
        switch inputMonitoring { case .granted, .denied: sourceParts.append("tcc-im"); default: break }

        if sourceParts.isEmpty { sourceParts = ["unknown"]; confidence = .low }

        let source = "kanata.\(sourceParts.joined(separator: "+"))"
        AppLogger.shared.log("🔮 [Oracle] Kanata permissions (TCC): AX=\(accessibility), IM=\(inputMonitoring) via \(source)")

        return PermissionSet(
            accessibility: accessibility,
            inputMonitoring: inputMonitoring,
            source: source,
            confidence: confidence,
            timestamp: Date()
        )
    }

    /// Functional verification disabled in TCP-only mode
    /// TCP connectivity check would require protocol implementation
    private func checkKanataFunctionalStatus() async -> Status {
        AppLogger.shared.log("🔮 [Oracle] Functional status check disabled (TCP-only mode)")
        return .unknown
    }

    /// Additional timeout wrapper to prevent hanging
    private func withTimeout<T: Sendable>(seconds: Double, operation: @Sendable @escaping () async -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw KeyPathError.permission(.privilegedOperationFailed(operation: "permission check", reason: "Operation timed out"))
            }

            guard let result = try await group.next() else {
                throw KeyPathError.permission(.privilegedOperationFailed(operation: "permission check", reason: "Operation timed out"))
            }

            group.cancelAll()
            return result
        }
    }

    // MARK: - Utilities

    // Add this helper to prefer the active daemon path, falling back to bundled path
    private func resolveKanataExecutablePath() -> String {
        let active = WizardSystemPaths.kanataActiveBinary
        if FileManager.default.fileExists(atPath: active) {
            return active
        }
        return WizardSystemPaths.bundledKanataPath
    }

    // MARK: - TCC Database Fallback (Necessary to break chicken-and-egg problem)

    // TCC service names across macOS versions
    private enum TCCServiceName: String {
        case accessibility = "kTCCServiceAccessibility"
        case inputMonitoring = "kTCCServiceListenEvent"
    }

    // Attempt to determine TCC status for Kanata by executable path (best-effort).
    // Returns (.granted/.denied) if determinable, or nil if inconclusive/unreadable.
    // NOTE: This direct TCC access was previously removed as "bad practice" but is
    // necessary here to resolve the chicken-and-egg problem between permission verification
    // and service startup. This is a legitimate fallback when functional verification fails.
    private func checkTCCForKanata(executablePath: String) async -> (ax: Status?, im: Status?) {
        // Normalize path for TCC queries - convert development builds to installed paths
        let normalizedPath = normalizePathForTCC(executablePath)
        let ax = await tccStatus(forExecutable: normalizedPath, service: .accessibility)
        let im = await tccStatus(forExecutable: normalizedPath, service: .inputMonitoring)
        return (ax, im)
    }

    /// Normalize paths for TCC queries - convert development builds to installed paths
    /// Development builds use paths like /Volumes/.../build/KeyPath.app/...
    /// But TCC database has the installed path /Applications/KeyPath.app/...
    private func normalizePathForTCC(_ path: String) -> String {
        // If this is a development build path, convert to installed path
        if path.contains("/build/KeyPath.app/") || path.contains("/.build") {
            // Extract the relative path after KeyPath.app/
            if let range = path.range(of: "/KeyPath.app/") {
                let relativePath = String(path[range.upperBound...])
                let canonicalPath = "/Applications/KeyPath.app/\(relativePath)"
                AppLogger.shared.log("🔮 [Oracle] Normalized TCC path: \(path) → \(canonicalPath)")
                return canonicalPath
            }
        }
        return path
    }

    // Query TCC DB for a specific executable path and service
    // Note: Requires Full Disk Access to read user's TCC.db; gracefully degrades to nil otherwise.
    // This is similar to how other system utilities (e.g., tccutil, privacy management tools) work.
    private func tccStatus(forExecutable execPath: String, service: TCCServiceName) async -> Status? {
        let dbPaths = tccDatabaseCandidates()
        for db in dbPaths where FileManager.default.fileExists(atPath: db) {
            if let val = await queryTCCDatabase(dbPath: db, service: service.rawValue, executablePath: execPath) {
                // Interpret result:
                // - Newer macOS: auth_value (2=Allow, 0=Deny or Prompt depending on auth_reason)
                // - Older macOS: allowed (1=Allow, 0=Not allowed)
                if val >= 2 || val == 1 {
                    return .granted
                } else if val == 0 {
                    // Only report denied if we positively read a 0 from TCC
                    return .denied
                }
            }
        }
        // Inconclusive (no readable DB, no rows found, or unexpected schema) => nil
        return nil
    }

    // TCC DB locations to try (user first, then system)
    // Most permission grants are stored in the user's TCC database
    private func tccDatabaseCandidates() -> [String] {
        let user = "\(NSHomeDirectory())/Library/Application Support/com.apple.TCC/TCC.db"
        let system = "/Library/Application Support/com.apple.TCC/TCC.db"
        return [user, system]
    }

    // Run a minimal sqlite query with a short timeout.
    // Returns an integer meaning of auth_value/allowed, or nil if not determinable.
    // Uses sqlite3 CLI tool which is available on all macOS systems.
    private func queryTCCDatabase(dbPath: String, service: String, executablePath: String) async -> Int? {
        // The 'access' table schema varies. We try auth_value first, then allowed.
        // We check for client_type=1 (path) because Kanata is a CLI binary.
        let escService = escapeSQLiteLiteral(service)
        let escExec = escapeSQLiteLiteral(executablePath)

        AppLogger.shared.log("🔍 [Oracle] Querying TCC database: \(dbPath)")
        AppLogger.shared.log("🔍 [Oracle] Looking for: service=\(service), path=\(executablePath)")

        let queries = [
            "SELECT auth_value FROM access WHERE service='\(escService)' AND client='\(escExec)' AND client_type=1 ORDER BY auth_value DESC LIMIT 1;",
            "SELECT allowed FROM access WHERE service='\(escService)' AND client='\(escExec)' AND client_type=1 ORDER BY allowed DESC LIMIT 1;"
        ]

        for (index, sql) in queries.enumerated() {
            AppLogger.shared.log("🔍 [Oracle] Trying query #\(index + 1)")
            if let out = await runSQLiteQuery(dbPath: dbPath, sql: sql, timeout: 0.4) {
                let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
                AppLogger.shared.log("🔍 [Oracle] Query #\(index + 1) returned: '\(trimmed)'")
                if let val = Int(trimmed) {
                    AppLogger.shared.log("🔍 [Oracle] TCC '\(service)' for \(executablePath) via \(dbPath): \(val)")
                    return val
                }
            } else {
                AppLogger.shared.log("🔍 [Oracle] Query #\(index + 1) returned nil (timeout or empty)")
            }
        }
        AppLogger.shared.log("🔍 [Oracle] TCC query failed for \(executablePath) - no results found")
        return nil
    }

    // Escape single quotes in SQL string literals to prevent injection
    private func escapeSQLiteLiteral(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "''")
    }

    // Execute sqlite3 query with timeout protection
    // This is a minimal, defensive implementation that avoids external dependencies
    private func runSQLiteQuery(dbPath: String, sql: String, timeout: Double) async -> String? {
        await withCheckedContinuation { continuation in
            Task.detached {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
                task.arguments = [dbPath, sql]

                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe

                var output: String?
                do {
                    try task.run()
                    // Implement a simple timeout by dispatching a kill if needed
                    let deadline = DispatchTime.now() + timeout
                    DispatchQueue.global().asyncAfter(deadline: deadline) {
                        if task.isRunning {
                            task.terminate() // best-effort timeout protection
                        }
                    }
                    task.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    output = String(data: data, encoding: .utf8)
                } catch {
                    AppLogger.shared.log("❌ [Oracle] sqlite3 query failed: \(error)")
                    output = nil
                }
                continuation.resume(returning: output)
            }
        }
    }
}

// MARK: - Status Display Helpers

public extension PermissionOracle.Status {
    var description: String {
        switch self {
        case .granted: "granted"
        case .denied: "denied"
        case let .error(msg): "error(\(msg))"
        case .unknown: "unknown"
        }
    }
}

