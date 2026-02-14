import AppKit
import Foundation
import KeyPathCore

@MainActor
class PermissionService {
    // MARK: - Static Instance

    static let shared = PermissionService()

    private init() {}

    // MARK: - 🔮 Oracle Era: Safe TCC Database API Only

    //
    // The PermissionService has been slimmed down to provide only safe,
    // deterministic TCC database reading methods used by PermissionOracle.
    //
    // All heuristic detection, permission checking, and complex logic
    // has been moved to PermissionOracle for single source of truth.

    // MARK: - Legacy Compatibility (Minimal Stubs)

    /// Legacy method stub - functionality moved to Oracle
    func clearCache() {
        AppLogger.shared.log("🔮 [PermissionService] clearCache() called - Oracle handles caching now")
    }

    /// Legacy method stub - opens Input Monitoring settings
    static func openInputMonitoringSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Legacy method stub - functionality moved to Oracle
    func markInputMonitoringPermissionGranted() {
        AppLogger.shared.log(
            "🔮 [PermissionService] markInputMonitoringPermissionGranted() - Oracle handles state now"
        )
    }

    /// Legacy compatibility for DI protocol
    struct SystemPermissionStatus {
        let keyPath: BinaryPermissionStatus
        let kanata: BinaryPermissionStatus
        var hasAllRequiredPermissions: Bool {
            false
        }
    }

    struct BinaryPermissionStatus {
        let binaryPath: String
        let hasInputMonitoring: Bool
        let hasAccessibility: Bool
        var hasAllRequiredPermissions: Bool {
            false
        }
    }

    /// Legacy method stub - use Oracle instead
    func checkSystemPermissions(kanataBinaryPath: String) -> SystemPermissionStatus {
        SystemPermissionStatus(
            keyPath: BinaryPermissionStatus(
                binaryPath: "", hasInputMonitoring: false, hasAccessibility: false
            ),
            kanata: BinaryPermissionStatus(
                binaryPath: kanataBinaryPath, hasInputMonitoring: false, hasAccessibility: false
            )
        )
    }

    /// Legacy method stub - use Oracle instead
    func verifyKanataFunctionalPermissions(at _: String)
        -> (
            hasInputMonitoring: Bool, hasAccessibility: Bool, confidence: String,
            verificationMethod: String, hasAllRequiredPermissions: Bool, errorDetails: [String]
        )
    {
        (
            hasInputMonitoring: false, hasAccessibility: false, confidence: "low",
            verificationMethod: "oracle-migration-stub", hasAllRequiredPermissions: false,
            errorDetails: []
        )
    }

    /// Legacy method stub - error analysis moved to Oracle
    static func analyzeKanataError(_: String) -> (
        isPermissionError: Bool, description: String, suggestedFix: String?
    ) {
        (
            isPermissionError: false, description: "Oracle system - see permission snapshot for details",
            suggestedFix: "Use Permission Oracle for diagnostics"
        )
    }

    /// Legacy stub for stale entry detection - returns array format
    static func detectPossibleStaleEntries() async -> (hasStaleEntries: Bool, details: [String]) {
        (hasStaleEntries: false, details: ["Oracle system - no stale entry detection needed"])
    }
}
