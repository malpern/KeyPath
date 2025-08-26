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

    /// Get current permission snapshot - THE authoritative permission state
    ///
    /// This is the ONLY method other components should call.
    /// No more direct PermissionService calls, no more guessing from logs.
    func currentSnapshot() async -> Snapshot {
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
        let keyPathSet = await checkKeyPathPermissions()

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
        let kanataPath = WizardSystemPaths.bundledKanataPath

        // Use functional verification as primary method for kanata permissions
        let functionalStatus = await checkKanataFunctionalStatus()

        // For accessibility, kanata typically doesn't need it, so use functional status
        let accessibility: Status = functionalStatus

        // For Input Monitoring, combine binary existence check with functional status
        let binaryCheck = checkBinaryInputMonitoring(at: kanataPath)
        let inputMonitoring: Status = switch (binaryCheck, functionalStatus) {
        case let (.error(msg), _):
            .error(msg) // Binary missing is definitive error
        case (_, .granted):
            .granted // Functional = granted means permissions work
        case (_, .denied):
            .denied // Functional = denied suggests permission issues
        case (_, .unknown):
            .unknown // Conservative when we can't verify
        case let (_, .error(msg)):
            .error(msg) // UDP errors
        }

        let source = "keypath.functional-verification"
        let confidence: Confidence = {
            if case .unknown = functionalStatus { return .low }
            return .high
        }()

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

        let client = KanataUDPClient(port: commSnapshot.udpPort, timeout: 1.0)
        let isConnected = await client.checkServerStatus()

        AppLogger.shared.log("🔮 [Oracle] Kanata functional check via UDP: \(isConnected ? "responding" : "not responding")")

        return isConnected ? .granted : .denied
    }

    // MARK: - Utilities (TCC fallback removed - UDP API is authoritative)

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
            await forceRefresh()
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
