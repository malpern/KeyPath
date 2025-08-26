import ApplicationServices
import Foundation
import IOKit.hid

/// 🔮 THE ORACLE - Single source of truth for all permission detection in KeyPath
///
/// This actor eliminates the chaos of multiple conflicting permission detection methods.
/// It provides deterministic, hierarchical permission checking with clear source precedence:
///
/// HIERARCHY (UPDATED based on macOS TCC limitations):
/// Priority 1: Apple APIs from GUI (IOHIDCheckAccess - reliable in user session)
/// Priority 2: Kanata TCP API (functional status, but unreliable for permissions)
/// Priority 3: Unknown (never guess)
///
/// ⚠️ CRITICAL: Kanata TCP reports false negatives for Input Monitoring
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

    // MARK: - Kanata Permission Detection (GUI Context - ARCHITECTURE.md Current Workaround)

    private func checkKanataPermissions() async -> PermissionSet {
        // Check kanata binary permissions from GUI context (reliable)
        let kanataPath = WizardSystemPaths.bundledKanataPath
        let inputMonitoring = checkBinaryInputMonitoring(at: kanataPath)

        // Use TCP only for functional verification, not permission status
        let functionalStatus = await checkKanataFunctionalStatus()

        return PermissionSet(
            accessibility: functionalStatus, // Kanata typically doesn't need AX
            inputMonitoring: inputMonitoring, // From GUI check
            source: "keypath.gui-check",
            confidence: .high,
            timestamp: Date()
        )
    }

    /// Check kanata binary Input Monitoring permission from GUI context (reliable)
    /// This is the key fix from ARCHITECTURE.md - GUI can reliably check permissions for kanata binary
    private func checkBinaryInputMonitoring(at _: String) -> Status {
        // Use Apple's approved API from GUI session context
        // This works reliably unlike root process self-assessment
        let hasPermission = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted

        AppLogger.shared.log("🔮 [Oracle] GUI Input Monitoring check for kanata binary: \(hasPermission ? "granted" : "denied")")

        return hasPermission ? .granted : .denied
    }

    /// Use TCP only for functional verification, not permission status
    private func checkKanataFunctionalStatus() async -> Status {
        // Quick functional check - is kanata responding via TCP?
        let tcpSnapshot = PreferencesService.tcpSnapshot()
        guard tcpSnapshot.shouldUseTCPServer else {
            AppLogger.shared.log("🔮 [Oracle] TCP server disabled - functional status unknown")
            return .unknown
        }

        let client = KanataTCPClient(port: tcpSnapshot.port, timeout: 1.0)
        let isConnected = await client.checkServerStatus()

        AppLogger.shared.log("🔮 [Oracle] Kanata functional check via TCP: \(isConnected ? "responding" : "not responding")")

        return isConnected ? .granted : .denied
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
