import ApplicationServices
import Foundation
import IOKit.hid

/// Errors that can occur during Oracle operations
enum OracleError: Error {
    case timeout
}

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
actor PermissionOracle {
    static let shared = PermissionOracle()

    // MARK: - Core Types

    enum Status {
        case granted
        case denied
        case error(String)
        case unknown

        var isReady: Bool {
            if case .granted = self { return true }
            return false
        }

        var isBlocking: Bool {
            if case .denied = self { return true }
            if case .error = self { return true }
            return false
        }
    }

    struct PermissionSet {
        let accessibility: Status
        let inputMonitoring: Status
        let source: String
        let confidence: Confidence
        let timestamp: Date

        var hasAllPermissions: Bool {
            accessibility.isReady && inputMonitoring.isReady
        }
    }

    struct Snapshot {
        let keyPath: PermissionSet
        let kanata: PermissionSet
        let timestamp: Date

        /// System is ready when both apps have all required permissions
        var isSystemReady: Bool {
            keyPath.hasAllPermissions && kanata.hasAllPermissions
        }

        /// Get the first blocking permission issue (user-facing error message)
        var blockingIssue: String? {
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
        var diagnosticSummary: String {
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

    enum Confidence {
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
    func invalidateCache() {
        AppLogger.shared.log("🔮 [Oracle] Cache invalidated - next check will be fresh")
        lastSnapshot = nil
        lastSnapshotTime = nil
    }

    /// Get current permission snapshot - THE authoritative permission state
    ///
    /// This is the ONLY method other components should call.
    /// No more direct PermissionService calls, no more guessing from logs.
    func currentSnapshot() async -> Snapshot {
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

        return snapshot
    }

    /// Force refresh (bypass cache) - use after permission changes
    func forceRefresh() async -> Snapshot {
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
        // This is much safer than the previous CGEvent tap approach
        let accessType = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let imGranted = accessType == kIOHIDAccessTypeGranted
        let inputMonitoring: Status = imGranted ? .granted : .denied

        let duration = Date().timeIntervalSince(start)
        AppLogger.shared.log("🔮 [Oracle] KeyPath permission check completed in \(String(format: "%.3f", duration))s - AX: \(accessibility), IM: \(inputMonitoring)")

        return PermissionSet(
            accessibility: accessibility,
            inputMonitoring: inputMonitoring,
            source: "keypath.official-apis",
            confidence: .high,
            timestamp: Date()
        )
    }

    // MARK: - Kanata Permission Detection (GUI Context - ARCHITECTURE.md Current Workaround)

    private func checkKanataPermissions() async -> PermissionSet {
        // ARCHITECTURE.md: Use split architecture - functional verification for root processes
        // Prefer the active binary path used by LaunchDaemon if available
        let kanataPath = resolveKanataExecutablePath()

        // 1) Primary: functional verification via UDP
        let functionalStatus = await checkKanataFunctionalStatus()

        var accessibility: Status = .unknown
        var inputMonitoring: Status = .unknown
        var sourceParts: [String] = []
        var confidence: Confidence = .low

        if case .granted = functionalStatus {
            // Positive functional signal: both permissions are effectively working
            accessibility = .granted
            inputMonitoring = .granted
            sourceParts.append("functional")
            confidence = .high
        } else {
            // 2) Secondary: TCC database fallback (best-effort, requires FDA)
            // NOTE: Direct TCC access is necessary here because functional verification
            // creates a chicken-and-egg problem: we can't start the service to verify
            // permissions if the wizard thinks permissions are missing, but we can't
            // verify permissions without starting the service. TCC fallback breaks this cycle.
            let (tccAX, tccIM) = await checkTCCForKanata(executablePath: kanataPath)

            if let ax = tccAX {
                accessibility = ax
                sourceParts.append("tcc-ax")
                if case .granted = ax { confidence = .high }
            }

            if let im = tccIM {
                inputMonitoring = im
                sourceParts.append("tcc-im")
                if case .granted = im { confidence = .high }
            }

            // Keep conservative stance if we still couldn't confirm via TCC
            if sourceParts.isEmpty {
                sourceParts.append("functional-unavailable")
                confidence = .low
            }
        }

        // Keep the binary existence check for logging only; don't mark permissions as error
        let binaryCheck = checkBinaryInputMonitoring(at: kanataPath)
        if case let .error(msg) = binaryCheck {
            AppLogger.shared.log("🔮 [Oracle] Kanata binary check: \(msg) (not treating as permission error)")
            // Do not override permission statuses here; component checks will handle missing binary
        }

        let source = "kanata.\(sourceParts.joined(separator: "+"))"
        AppLogger.shared.log("🔮 [Oracle] Kanata permissions: AX=\(accessibility), IM=\(inputMonitoring) via \(source)")

        return PermissionSet(
            accessibility: accessibility,
            inputMonitoring: inputMonitoring,
            source: source,
            confidence: confidence,
            timestamp: Date()
        )
    }

    /// Check kanata binary Input Monitoring permission using functional verification
    /// Since IOHIDCheckAccess() is unreliable for root processes, we use UDP functional testing
    private func checkBinaryInputMonitoring(at kanataPath: String) -> Status {
        // ARCHITECTURE.md: Root processes have unreliable IOHIDCheckAccess() results
        // Instead, we verify functionality via UDP if kanata is running with permissions

        // First check if the binary exists
        guard FileManager.default.fileExists(atPath: kanataPath) else {
            AppLogger.shared.log("🔮 [Oracle] Kanata binary not found at \(kanataPath)")
            return .error("Kanata binary not found")
        }

        // For Input Monitoring, the most reliable test is functional verification:
        // If kanata UDP server is responding, it likely has the required permissions
        // This avoids the IOHIDCheckAccess() reliability issues for root processes

        let commSnapshot = PreferencesService.communicationSnapshot()
        guard commSnapshot.shouldUseUDP else {
            AppLogger.shared.log("🔮 [Oracle] UDP disabled - cannot verify kanata Input Monitoring via functional test")
            // Fallback: assume permissions are needed (conservative approach)
            return .unknown
        }

        // Note: We can't do synchronous UDP check here without blocking
        // The functional check happens in checkKanataFunctionalStatus()
        // For now, assume .unknown and let functional verification handle it
        AppLogger.shared.log("🔮 [Oracle] Input Monitoring check deferred to functional verification")
        return .unknown
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
                throw OracleError.timeout
            }
            
            guard let result = try await group.next() else {
                throw OracleError.timeout
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
            
            // Look for lines containing "*.port" or "127.0.0.1.port" indicating a listening server
            let listeningPattern = "\\*\\.\(port)\\s"
            let localhostPattern = "127\\.0\\.0\\.1\\.\(port)\\s"
            
            let listeningRegex = try NSRegularExpression(pattern: listeningPattern)
            let localhostRegex = try NSRegularExpression(pattern: localhostPattern)
            
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            let hasWildcardListener = listeningRegex.firstMatch(in: output, range: range) != nil
            let hasLocalhostListener = localhostRegex.firstMatch(in: output, range: range) != nil
            
            let isListening = hasWildcardListener || hasLocalhostListener
            AppLogger.shared.log("🔍 [Oracle] Port \(port) listening check: \(isListening)")
            return isListening
            
        } catch {
            AppLogger.shared.log("❌ [Oracle] Error checking UDP port \(port): \(error)")
            // On error, assume port might be listening to avoid false negatives
            return true
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
        let ax = await tccStatus(forExecutable: executablePath, service: .accessibility)
        let im = await tccStatus(forExecutable: executablePath, service: .inputMonitoring)
        return (ax, im)
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
    var description: String {
        switch self {
        case .granted: "granted"
        case .denied: "denied"
        case let .error(msg): "error(\(msg))"
        case .unknown: "unknown"
        }
    }
}

extension PermissionOracle.Confidence: CustomStringConvertible {
    var description: String {
        switch self {
        case .high: "high"
        case .low: "low"
        }
    }
}
