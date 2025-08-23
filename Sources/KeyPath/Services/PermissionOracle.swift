import ApplicationServices
import Foundation
import IOKit.hid

/// 🔮 THE ORACLE - Single source of truth for all permission detection in KeyPath
///
/// This actor eliminates the chaos of multiple conflicting permission detection methods.
/// It provides deterministic, hierarchical permission checking with clear source precedence:
///
/// Priority 1: Kanata TCP API (authoritative from process that needs permissions)
/// Priority 2: Official Apple APIs (AXIsProcessTrusted, IOHIDCheckAccess)
/// Priority 3: Unknown (never guess, never parse logs, TCC fallback removed)
///
/// With PR #1759, we get authoritative permission data directly from kanata itself.
/// No more log parsing. No more error pattern matching. No more conflicting results.
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
        case high // TCP API, Official Apple APIs
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

    /// Get current permission snapshot - THE authoritative permission state
    ///
    /// This is the ONLY method other components should call.
    /// No more direct PermissionService calls, no more guessing from logs.
    func currentSnapshot() async -> Snapshot {
        // Return cached result if fresh
        if let cachedTime = lastSnapshotTime,
           let cached = lastSnapshot,
           Date().timeIntervalSince(cachedTime) < cacheTTL
        {
            AppLogger.shared.log("🔮 [Oracle] Returning cached snapshot (age: \(String(format: "%.3f", Date().timeIntervalSince(cachedTime)))s)")
            return cached
        }

        AppLogger.shared.log("🔮 [Oracle] Generating fresh permission snapshot")
        let start = Date()

        // Get KeyPath permissions (local, always authoritative)
        let keyPathSet = await checkKeyPathPermissions()

        // Get Kanata permissions (TCP primary, TCC fallback)
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

    // MARK: - Kanata Permission Detection (TCP Authoritative)

    private func checkKanataPermissions() async -> PermissionSet {
        // Primary: TCP API (authoritative from Kanata itself)
        if let tcpResult = await checkKanataViaTCP() {
            return tcpResult
        }

        AppLogger.shared.log("🔮 [Oracle] TCP unavailable - kanata service not running or TCP disabled")

        // With PR #1759, we have authoritative permission data from kanata itself
        // No more TCC database fallback - unknown is better than potentially incorrect data
        return PermissionSet(
            accessibility: .unknown,
            inputMonitoring: .unknown,
            source: "kanata.tcp-unavailable",
            confidence: .low,
            timestamp: Date()
        )
    }

    private func checkKanataViaTCP() async -> PermissionSet? {
        // Check if TCP is enabled and get port
        let tcpSnapshot = PreferencesService.tcpSnapshot()
        guard tcpSnapshot.shouldUseTCPServer else {
            AppLogger.shared.log("🔮 [Oracle] TCP server disabled in preferences")
            return nil
        }

        let client = KanataTCPClient(port: tcpSnapshot.port, timeout: 1.2)

        // Quick server availability check
        guard await client.checkServerStatus() else {
            AppLogger.shared.log("🔮 [Oracle] Kanata TCP server not reachable at port \(tcpSnapshot.port)")
            return nil
        }

        do {
            let status = try await client.checkMacOSPermissions()
            let accessibility = mapKanataStatusField(status.accessibility)
            let inputMonitoring = mapKanataStatusField(status.input_monitoring)

            AppLogger.shared.log("🔮 [Oracle] ✅ Kanata TCP permission check successful")
            return PermissionSet(
                accessibility: accessibility,
                inputMonitoring: inputMonitoring,
                source: "kanata.tcp-authoritative",
                confidence: .high,
                timestamp: Date()
            )
        } catch {
            AppLogger.shared.log("🔮 [Oracle] ❌ Kanata TCP permission check failed: \(error)")
            return nil
        }
    }

    private func mapKanataStatusField(_ field: String) -> Status {
        switch field.lowercased() {
        case "granted": .granted
        case "denied": .denied
        case "error": .error("kanata reported error")
        default: .unknown
        }
    }

    // MARK: - Utilities (TCC fallback removed - TCP API is authoritative)

    // MARK: - TCP Restart Integration

    /// Restart Kanata after permission changes (if TCP available)
    func restartKanataAfterPermissionChange() async -> Bool {
        let tcpSnapshot = PreferencesService.tcpSnapshot()
        guard tcpSnapshot.shouldUseTCPServer else {
            AppLogger.shared.log("🔮 [Oracle] TCP disabled, cannot restart Kanata via TCP")
            return false
        }

        let client = KanataTCPClient(port: tcpSnapshot.port, timeout: 2.0)
        let success = await client.restartKanata()

        if success {
            AppLogger.shared.log("🔮 [Oracle] ✅ Kanata restarted successfully via TCP")
            // Invalidate cache to force fresh permission check
            await forceRefresh()
        } else {
            AppLogger.shared.log("🔮 [Oracle] ❌ Failed to restart Kanata via TCP")
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
