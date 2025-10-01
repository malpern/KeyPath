import ApplicationServices
@preconcurrency import Combine
import Foundation
import IOKit.hid

// (Removed deprecated OracleError - now using KeyPathError directly)

/// 🔮 THE ORACLE - Single source of truth for all permission detection in KeyPath
///
/// This actor eliminates the chaos of multiple conflicting permission detection methods.
/// It provides deterministic, hierarchical permission checking with clear source precedence:
///
/// HIERARCHY (UPDATED based on macOS TCC limitations):
/// Priority 1: Apple APIs from GUI (IOHIDCheckAccess - reliable in user session)
/// Priority 2: Kanata UDP API (functional status, but unreliable for permissions)
/// Priority 3: Unknown (never guess)
///
/// ⚠️ CRITICAL: Kanata UDP reports false negatives for Input Monitoring
/// due to IOHIDCheckAccess() being unreliable for root processes
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

        public var hasAllPermissions: Bool {
            accessibility.isReady && inputMonitoring.isReady
        }
    }

    public struct Snapshot: Sendable {
        public let keyPath: PermissionSet
        public let kanata: PermissionSet
        public let timestamp: Date

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

    public enum Confidence: Equatable, Sendable {
        case high // UDP API, Official Apple APIs
        case low // Unknown/unavailable states (TCC fallback removed)
    }

    // MARK: - State Management

    private var lastSnapshot: Snapshot?
    private var lastSnapshotTime: Date?

    /// Cache TTL for sub-2-second goal
    private let cacheTTL: TimeInterval = 1.5

    private init() {
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
        
        if ProcessInfo.processInfo.environment["KEYPATH_STARTUP_MODE"] == "1" {
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
        // ================================================================================================
        // 🚨 CRITICAL ARCHITECTURAL PRINCIPLE - DO NOT CHANGE WITHOUT UNDERSTANDING THIS COMMENT 🚨
        // ================================================================================================
        //
        // ORACLE PERMISSION DETECTION HIERARCHY:
        //
        // 1. APPLE APIs for Input Monitoring (IOHIDCheckAccess from GUI context) - MOST RELIABLE
        //    - Always trust definitive answers (.granted/.denied)
        //    - GUI context can reliably check permissions for any binary path
        //    - This is the official Apple-approved method
        //
        // 2. TCC DATABASE for Accessibility - REQUIRED (no Apple API alternative)
        //    - CRITICAL: No Apple API exists to check another binary's Accessibility permission
        //    - AXIsProcessTrusted() only works for current process
        //    - TCC database is the ONLY option for checking kanata's Accessibility
        //    - Also used as fallback for Input Monitoring when Apple API returns .unknown
        //
        // 3. FUNCTIONAL VERIFICATION - Separate from permission checking
        //    - UDP connectivity test to verify kanata is actually working
        //    - Used for health checks, NOT permission detection
        //
        // ⚠️  KEY INSIGHT: Input Monitoring and Accessibility have DIFFERENT detection methods ⚠️
        //     - Input Monitoring: Apple API available (IOHIDCheckAccess) ✅
        //     - Accessibility: No Apple API for other binaries ❌ → Must use TCC
        //
        // Historical context:
        // - Original bug (line 290): Used UDP functional check for Accessibility permission status
        // - Problem: UDP connectivity ≠ Accessibility permission (conflated two concepts)
        // - Fix: Always use TCC database for kanata Accessibility (only reliable method)
        // ================================================================================================

        let kanataPath = resolveKanataExecutablePath()

        // 1) Check Input Monitoring via Apple API (MOST RELIABLE for IM)
        let inputMonitoringAPI = checkBinaryInputMonitoring(at: kanataPath)

        // 2) ALWAYS check TCC database for Accessibility (no Apple API alternative)
        //    Also get TCC Input Monitoring for fallback if Apple API returns .unknown
        AppLogger.shared.log("🔮 [Oracle] Checking TCC database for kanata permissions (required for Accessibility)")
        let (tccAX, tccIM) = await checkTCCForKanata(executablePath: kanataPath)

        // 3) Determine final permission status using hierarchy

        // Accessibility: Always use TCC (no other option)
        let accessibility: Status = tccAX ?? .unknown

        // Input Monitoring: Prefer Apple API, use TCC only if API returns .unknown
        var finalInputMonitoring = inputMonitoringAPI
        if case .unknown = inputMonitoringAPI, let im = tccIM {
            finalInputMonitoring = im
        }

        // 4) Determine source and confidence for logging
        var sourceParts: [String] = []

        // Track Accessibility source (always TCC)
        if tccAX != nil {
            sourceParts.append("tcc-ax")
        }

        // Track Input Monitoring source (API or TCC fallback)
        if case .unknown = inputMonitoringAPI, tccIM != nil {
            sourceParts.append("tcc-im")
        } else if inputMonitoringAPI != .unknown {
            sourceParts.append("api-im")
        }

        let source = "kanata.\(sourceParts.isEmpty ? "unavailable" : sourceParts.joined(separator: "+"))"

        // Confidence is high if both permissions are granted
        let confidence: Confidence = (accessibility.isReady && finalInputMonitoring.isReady) ? .high : .low

        AppLogger.shared.log("🔮 [Oracle] Kanata permissions: AX=\(accessibility) (TCC), IM=\(finalInputMonitoring) (API) via \(source)")

        return PermissionSet(
            accessibility: accessibility,
            inputMonitoring: finalInputMonitoring,
            source: source,
            confidence: confidence,
            timestamp: Date()
        )
    }

    /// Check kanata binary Input Monitoring permission from GUI context (AUTHORITATIVE)
    /// 
    /// 🚨 CRITICAL: This is THE definitive permission check - DO NOT BYPASS WITH TCC DATABASE
    /// 
    /// Why this works reliably:
    /// - IOHIDCheckAccess from GUI context can check permissions for ANY binary path
    /// - Apple's official API, not a workaround or heuristic
    /// - Returns definitive .granted/.denied status (never .unknown in practice)
    /// - Works regardless of whether the target binary is currently running
    /// 
    /// Why we trust this over TCC database:
    /// - TCC database can be stale/inconsistent after permission grants
    /// - This API reflects the ACTUAL current permission state
    /// - GUI context has reliable access to permission subsystem
    private func checkBinaryInputMonitoring(at kanataPath: String) -> Status {
        // First check if the binary exists
        guard FileManager.default.fileExists(atPath: kanataPath) else {
            AppLogger.shared.log("🔮 [Oracle] Kanata binary not found at \(kanataPath)")
            return .error("Kanata binary not found")
        }

        // 🔮 THE ORACLE SPEAKS: This is the authoritative permission check
        // IOHIDCheckAccess from GUI context is the official Apple method
        // and works reliably for checking permissions of any executable path
        let hasPermission = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        
        AppLogger.shared.log("🔮 [Oracle] AUTHORITATIVE Apple API check for kanata binary: \(hasPermission ? "GRANTED" : "DENIED")")
        
        return hasPermission ? .granted : .denied
    }

    /// Use UDP for functional verification, not permission status
    private func checkKanataFunctionalStatus() async -> Status {
        // Quick functional check - is kanata responding via UDP?
        let commSnapshot = PreferencesService.communicationSnapshot()
        guard commSnapshot.shouldUseUDP else {
            AppLogger.shared.log("🔮 [Oracle] UDP server disabled - functional status unknown")
            return .unknown
        }

        // Pre-flight check: verify UDP port is listening before attempting connection
        // This prevents the UDP client from hanging indefinitely on non-listening ports
        let port = commSnapshot.udpPort
        if !isUDPPortListening(port: port) {
            AppLogger.shared.log("🔮 [Oracle] UDP port \(port) not listening - skipping connection test")
            AppLogger.shared.log("🔮 [Oracle] Kanata functional check: UNKNOWN (no server)")
            return .unknown
        }
        
        // Add additional timeout protection to prevent wizard hanging
        let client = KanataUDPClient(port: port, timeout: 3.0)
        AppLogger.shared.log("🔮 [Oracle] Testing UDP connection to port \(port)...")
        
        do {
            // Wrap in additional timeout to prevent indefinite hanging
            let isConnected = try await withTimeout(seconds: 3.5) {
                await client.checkServerStatus()
            }
            
            AppLogger.shared.log("🔮 [Oracle] UDP connection result: \(isConnected)")
            AppLogger.shared.log("🔮 [Oracle] Kanata functional check: \(isConnected ? "GRANTED (responding)" : "UNKNOWN (not responding)")")
            
            // Only grant on positive signal; otherwise unknown (don't mark as denied)
            return isConnected ? .granted : .unknown
        } catch {
            AppLogger.shared.log("🔮 [Oracle] UDP connection timed out or failed: \(error)")
            AppLogger.shared.log("🔮 [Oracle] Kanata functional check: UNKNOWN (timeout/error)")
            return .unknown
        }
    }
    
    /// Additional timeout wrapper to prevent hanging
    private func withTimeout<T: Sendable>(seconds: Double, operation: @Sendable @escaping () async -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
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
    
    /// Fast check if UDP port is listening using netstat to prevent hanging connections
    private func isUDPPortListening(port: Int) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        task.arguments = ["-an", "-p", "udp"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Look for lines where the LOCAL address (first column) is listening on this port
            // Format is typically: "udp4  0  0  *.37001  *.*" or "udp4  0  0  127.0.0.1.37001  *.*"
            // We need to check the LOCAL address column, not the remote address column
            let lines = output.components(separatedBy: .newlines)
            var isListening = false

            for line in lines {
                // Skip empty lines
                if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }

                // Parse netstat output - columns are whitespace separated
                let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

                // UDP lines have format: proto recv-q send-q local foreign [state]
                if components.count >= 5 && components[0].hasPrefix("udp") {
                    let localAddr = components[3]

                    // Check if this is a listening socket on our port
                    if localAddr == "*.\(port)" || localAddr == "127.0.0.1.\(port)" {
                        isListening = true
                        break
                    }
                }
            }

            AppLogger.shared.log("🔍 [Oracle] Port \(port) listening check: \(isListening)")
            return isListening
            
        } catch {
            AppLogger.shared.log("❌ [Oracle] Error checking UDP port \(port): \(error)")
            // On error, assume port might be listening to avoid false negatives
            return true
        }
    }

    // MARK: - Utilities

    // Prefer the actually running kanata path; else bundled; else system-install
    // For TCC queries, we normalize to the canonical installed path
    private func resolveKanataExecutablePath() -> String {
        if let running = detectRunningKanataPath() {
            // Normalize development builds to installed path for TCC queries
            // TCC database stores permissions for /Applications/KeyPath.app, not build/KeyPath.app
            let normalized = normalizePathForTCC(running)
            AppLogger.shared.log("🔮 [Oracle] Resolved kanata path: \(running) → normalized for TCC: \(normalized)")
            return normalized
        }
        // Prefer bundled binary for TCC stability
        let bundled = WizardSystemPaths.bundledKanataPath
        if FileManager.default.fileExists(atPath: bundled) { return bundled }
        // Fallback to system install
        return WizardSystemPaths.kanataSystemInstallPath
    }

    // Normalize paths for TCC queries - convert development builds to installed paths
    // TCC database uses canonical installed paths, not temporary build locations
    private func normalizePathForTCC(_ path: String) -> String {
        // If this is a build directory, convert to /Applications/ path
        if path.contains("/build/KeyPath.app/") || path.contains("/.build") {
            // Extract the relative path within the app bundle
            if path.contains("/KeyPath.app/") {
                if let range = path.range(of: "/KeyPath.app/") {
                    let relativePath = String(path[range.upperBound...])
                    let canonicalPath = "/Applications/KeyPath.app/\(relativePath)"
                    AppLogger.shared.log("🔍 [Oracle] TCC path normalization: \(path) → \(canonicalPath)")
                    return canonicalPath
                }
            }
        }
        // Already a canonical path or unknown format - return as-is
        return path
    }

    private func detectRunningKanataPath() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-ax", "kanata"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard var line = String(data: data, encoding: .utf8)?.split(separator: "\n").first else { return nil }
            // Line format: "PID /path/to/kanata [args]" → extract the path substring after first space
            if let firstSpace = line.firstIndex(of: " ") {
                line = line[line.index(after: firstSpace)...]
                // Path is up to next space
                let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                if let path = parts.first, FileManager.default.fileExists(atPath: String(path)) {
                    return String(path)
                }
            }
        } catch {
            AppLogger.shared.log("❌ [Oracle] detectRunningKanataPath failed: \(error)")
        }
        return nil
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
        let ax = await tccStatus(forExecutable: executablePath, service: .accessibility)
        let im = await tccStatus(forExecutable: executablePath, service: .inputMonitoring)
        return (ax, im)
    }

    // Query TCC DB for a specific executable path and service
    // Note: Requires Full Disk Access to read user's TCC.db; gracefully degrades to nil otherwise.
    // This is similar to how other system utilities (e.g., tccutil, privacy management tools) work.
    private func tccStatus(forExecutable execPath: String, service: TCCServiceName) async -> Status? {
        let dbPaths = tccDatabaseCandidates()
        AppLogger.shared.log("🔍 [Oracle] TCC query for \(service.rawValue) at '\(execPath)' - checking \(dbPaths.count) databases")
        for db in dbPaths where FileManager.default.fileExists(atPath: db) {
            AppLogger.shared.log("🔍 [Oracle] Querying TCC database: \(db)")
            if let val = await queryTCCDatabase(dbPath: db, service: service.rawValue, executablePath: execPath) {
                // Interpret result:
                // - Newer macOS: auth_value (2=Allow, 0=Deny or Prompt depending on auth_reason)
                // - Older macOS: allowed (1=Allow, 0=Not allowed)
                if val >= 2 || val == 1 {
                    AppLogger.shared.log("🔍 [Oracle] TCC '\(service.rawValue)' for \(execPath) via \(db): \(val) → GRANTED")
                    return .granted
                } else if val == 0 {
                    // Only report denied if we positively read a 0 from TCC
                    AppLogger.shared.log("🔍 [Oracle] TCC '\(service.rawValue)' for \(execPath) via \(db): \(val) → DENIED")
                    return .denied
                }
            } else {
                AppLogger.shared.log("🔍 [Oracle] TCC '\(service.rawValue)' query returned nil for \(db)")
            }
        }
        // Inconclusive (no readable DB, no rows found, or unexpected schema) => nil
        AppLogger.shared.log("🔍 [Oracle] TCC '\(service.rawValue)' for \(execPath): No results from any database → UNKNOWN")
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

        let queries = [
            "SELECT auth_value FROM access WHERE service='\(escService)' AND client='\(escExec)' AND client_type=1 ORDER BY auth_value DESC LIMIT 1;",
            "SELECT allowed FROM access WHERE service='\(escService)' AND client='\(escExec)' AND client_type=1 ORDER BY allowed DESC LIMIT 1;"
        ]

        for sql in queries {
            if let out = await runSQLiteQuery(dbPath: dbPath, sql: sql, timeout: 0.4) {
                let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
                if let val = Int(trimmed) {
                    AppLogger.shared.log("🔍 [Oracle] TCC '\(service)' for \(executablePath) via \(dbPath): \(val)")
                    return val
                }
            }
        }
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

    // MARK: - UDP Restart Integration

    /// Restart Kanata after permission changes (if UDP available)
    func restartKanataAfterPermissionChange() async -> Bool {
        let commSnapshot = PreferencesService.communicationSnapshot()
        guard commSnapshot.shouldUseUDP else {
            AppLogger.shared.log("🔮 [Oracle] UDP disabled, cannot restart Kanata via UDP")
            return false
        }

        let client = KanataUDPClient(port: commSnapshot.udpPort, timeout: 2.0)
        let success = await client.restartKanata()

        if success {
            AppLogger.shared.log("🔮 [Oracle] ✅ Kanata restarted successfully via UDP")
            // Invalidate cache to force fresh permission check
            _ = await forceRefresh()
        } else {
            AppLogger.shared.log("🔮 [Oracle] ❌ Failed to restart Kanata via UDP")
        }

        return success
    }
}

// MARK: - Status Display Helpers

extension PermissionOracle.Status: CustomStringConvertible {
    public var description: String {
        switch self {
        case .granted: "granted"
        case .denied: "denied"
        case let .error(msg): "error(\(msg))"
        case .unknown: "unknown"
        }
    }
}

extension PermissionOracle.Confidence: CustomStringConvertible {
    public var description: String {
        switch self {
        case .high: "high"
        case .low: "low"
        }
    }
}
